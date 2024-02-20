# LXLY BRIDGE AND CALL

## Testing and Deploying

First, copy `.env.example` to `.env` and set the appropriate environment variables (annotated with TODOs).

### Testing (Mainnet Forks)

1. Start anvil: two instances required, one for L1, and one for L2

```bash
# 1.1 start L1 (ethereum mainnet) anvil - NOTE: using port 8001 for L1
anvil --fork-url <https://eth-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY> --chain-id 1 --port 8001 --fork-block-number 19270231

# 1.2 start L2 (polygon zkevm) anvil - NOTE: using port 8101 for L2
anvil --fork-url <https://polygonzkevm-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY> --chain-id 1101 --port 8101 --fork-block-number 10087380
```

2. Run the tests

```bash
forge test --evm-version shanghai -vvvvv
```

or

```
forge test --evm-version shanghai -vvvvv --match-contract NativeConverter
forge test --evm-version shanghai -vvvvv --match-contract QuickSwap
forge test --evm-version shanghai -vvvvv --match-contract KEOM
```

### Deployment (Mainnet Forks)

TODO
