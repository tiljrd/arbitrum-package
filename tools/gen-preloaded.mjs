#!/usr/bin/env node
import fs from 'node:fs';
import process from 'node:process';

function usage(msg) {
  if (msg) console.error(msg);
  console.error('Usage: node tools/gen-preloaded.mjs --rpc <url> --contracts <contracts.json> [--block latest|0xHEX|NUMBER] [--out preloaded.json] [--encoding eth|wei] [--extra extra.json]');
  process.exit(1);
}

function parseArgs() {
  const args = {};
  for (let i = 2; i < process.argv.length; i++) {
    const k = process.argv[i];
    if (!k.startsWith('--')) usage(`Unexpected arg: ${k}`);
    const next = process.argv[i + 1];
    if (!next || next.startsWith('--')) {
      usage(`Missing value for ${k}`);
    }
    args[k.slice(2)] = next;
    i++;
  }
  if (!args.rpc || !args.contracts) usage();
  args.block = args.block ?? 'latest';
  args.out = args.out ?? 'preloaded.json';
  args.encoding = (args.encoding ?? 'eth').toLowerCase();
  if (!['eth', 'wei'].includes(args.encoding)) usage('encoding must be eth or wei');
  return args;
}

async function rpc(rpcUrl, method, params) {
  const res = await fetch(rpcUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });
  const data = await res.json();
  if (data.error) throw new Error(`${method} error: ${JSON.stringify(data.error)}`);
  return data.result;
}

function toHexBlockTag(block) {
  if (block === 'latest' || block === 'earliest' || block === 'pending' || block === 'safe' || block === 'finalized') return block;
  if (typeof block === 'string' && block.startsWith('0x')) return block;
  const n = BigInt(block);
  return '0x' + n.toString(16);
}

function toEthStringFromHexWei(hexWei) {
  const wei = BigInt(hexWei);
  const denom = 10n ** 18n;
  const whole = wei / denom;
  const frac = wei % denom;
  const fracStr = frac.toString().padStart(18, '0').replace(/0+$/, '');
  return fracStr.length ? `${whole}.${fracStr}ETH` : `${whole}ETH`;
}

async function tryDumpBlock(rpcUrl, blockTag) {
  try {
    const result = await rpc(rpcUrl, 'debug_dumpBlock', [blockTag]);
    return result;
  } catch (e) {
    if (String(e).includes('Method not found')) {
      console.warn('WARN: debug_dumpBlock not available; will fall back to individual RPCs and storageRangeAt if available.');
      return null;
    }
    throw e;
  }
}

async function getBlockHash(rpcUrl, blockTag) {
  // blockTag is hex number like 0x2b or 'latest'
  const block = await rpc(rpcUrl, 'eth_getBlockByNumber', [blockTag, false]);
  if (!block || !block.hash) throw new Error(`eth_getBlockByNumber returned no hash for ${blockTag}`);
  return block.hash;
}

async function dumpStorageRangeAt(rpcUrl, addr, blockTag) {
  const storage = {};
  let nextKey = null;
  let pages = 0;
  let blockHash;
  try {
    blockHash = await getBlockHash(rpcUrl, blockTag);
  } catch (e) {
    // If we cannot get the block hash, fall back to empty storage
    return { storage, complete: false, methodAvailable: false };
  }
  while (true) {
    let res;
    try {
      // Geth signature: debug_storageRangeAt(blockHash, txIndex, address, startKey, maxResults)
      res = await rpc(rpcUrl, 'debug_storageRangeAt', [blockHash, 0, addr, nextKey ?? '0x', 1024]);
    } catch (e) {
      if (String(e).includes('Method not found')) {
        return { storage, complete: false, methodAvailable: false };
      }
      throw e;
    }
    const page = res?.storage || {};
    for (const [slot, entry] of Object.entries(page)) {
      const val = entry?.value || '0x0';
      if (val !== '0x0' && val !== '0x' && val !== '0x00') storage[slot.toLowerCase()] = val;
    }
    pages++;
    if (!res?.nextKey || pages > 10000) break;
    nextKey = res.nextKey;
  }
  return { storage, complete: true, methodAvailable: true };
}

async function main() {
  const args = parseArgs();
  const rpcUrl = args.rpc;
  const contracts = JSON.parse(fs.readFileSync(args.contracts, 'utf8'));
  const extra = args.extra ? JSON.parse(fs.readFileSync(args.extra, 'utf8')) : [];
  const blockTag = toHexBlockTag(args.block);

  const addrs = new Set();
  Object.values(contracts).forEach(a => addrs.add(String(a).toLowerCase()));
  if (Array.isArray(extra)) {
    extra.forEach(a => addrs.add(String(a).toLowerCase()));
  } else if (extra && typeof extra === 'object') {
    Object.values(extra).forEach(a => addrs.add(String(a).toLowerCase()));
  }

  let dump = null;
  if (blockTag === 'latest') {
    const bnHex = await rpc(rpcUrl, 'eth_blockNumber', []);
    dump = await tryDumpBlock(rpcUrl, bnHex);
  } else {
    dump = await tryDumpBlock(rpcUrl, blockTag);
  }

  let accounts = {};
  if (dump && dump.accounts) {
    accounts = dump.accounts;
  } else if (dump) {
    accounts = dump;
  }

  const out = {};

  for (const addr of addrs) {
    let code = '0x';
    let balanceHex = '0x0';
    let nonceHex = '0x0';
    let storageObj = {};

    const accDump = accounts[addr] || accounts[addr?.toLowerCase?.()] || accounts[addr?.toUpperCase?.()];
    if (accDump) {
      if (accDump.code) code = accDump.code;
      if (accDump.balance) balanceHex = accDump.balance;
      if (typeof accDump.nonce !== 'undefined') {
        nonceHex = typeof accDump.nonce === 'string' ? accDump.nonce : '0x' + BigInt(accDump.nonce).toString(16);
      }
      if (accDump.storage && typeof accDump.storage === 'object') {
        for (const [slot, val] of Object.entries(accDump.storage)) {
          if (val && val !== '0x' && val !== '0x0' && val !== '0x00') {
            storageObj[slot.toLowerCase()] = val;
          }
        }
      }
    }

    if (code === '0x') {
      code = await rpc(rpcUrl, 'eth_getCode', [addr, blockTag]);
    }
    if (balanceHex === '0x0') {
      balanceHex = await rpc(rpcUrl, 'eth_getBalance', [addr, blockTag]);
    }
    if (nonceHex === '0x0') {
      nonceHex = await rpc(rpcUrl, 'eth_getTransactionCount', [addr, blockTag]);
    }

    if (Object.keys(storageObj).length === 0) {
      const { storage } = await dumpStorageRangeAt(rpcUrl, addr, blockTag);
      storageObj = storage;
    }

    const entry = {
      balance: args.encoding === 'wei' ? balanceHex : toEthStringFromHexWei(balanceHex),
      code,
      storage: storageObj,
      nonce: Number(BigInt(nonceHex)),
      secretKey: '0x',
    };
    out[addr] = entry;
  }

  fs.writeFileSync(args.out, JSON.stringify(out, null, 2));
  console.log(`Wrote ${args.out}`);
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
