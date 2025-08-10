#!/usr/bin/env node
import fs from 'node:fs';
import process from 'node:process';

function usage(msg) {
  if (msg) console.error(msg);
  console.error('Usage: node tools/gen-genesis-info.mjs --deployed <deployed_chain_info.json> [--l2config <l2_chain_config.json>] [--name <chain-name>] --out <l2_chain_info.genesis.json>');
  process.exit(1);
}

function parseArgs() {
  const args = {};
  for (let i = 2; i < process.argv.length; i++) {
    const k = process.argv[i];
    if (!k.startsWith('--')) usage(`Unexpected arg: ${k}`);
    const next = process.argv[i + 1];
    if (!next || next.startsWith('--')) usage(`Missing value for ${k}`);
    args[k.slice(2)] = next;
    i++;
  }
  if (!args.deployed || !args.out) usage();
  return args;
}

function readJSON(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function buildFromDeployed(deployed, l2config, name) {
  const first = Array.isArray(deployed) ? deployed[0] : deployed;
  const chainName = name || first?.['chain-name'] || 'ArbitrumLocalPreloaded';
  const parentChainId = first?.['parent-chain-id'] ?? first?.chain_config?.l1?.chain_id;
  const parentIsArb = false;

  const chainConfig = l2config || first?.['chain-config'] || {};
  const rollup = first?.rollup || {};

  return [
    {
      'chain-name': chainName,
      'parent-chain-id': parentChainId,
      'parent-chain-is-arbitrum': parentIsArb,
      'sequencer-url': first?.['sequencer-url'] || '',
      'secondary-forwarding-target': first?.['secondary-forwarding-target'] || '',
      'feed-url': first?.['feed-url'] || '',
      'secondary-feed-url': first?.['secondary-feed-url'] || '',
      'das-index-url': first?.['das-index-url'] || '',
      'has-genesis-state': true,
      'chain-config': chainConfig,
      'rollup': rollup,
    },
  ];
}

async function main() {
  const args = parseArgs();
  const deployed = readJSON(args.deployed);
  const l2cfg = args.l2config ? readJSON(args.l2config) : null;
  const out = buildFromDeployed(deployed, l2cfg, args.name);
  fs.writeFileSync(args.out, JSON.stringify(out, null, 2));
  console.log(`Wrote ${args.out}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
