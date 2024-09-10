# uLXLY BRIDGE AND CALL

## Testing and Deploying

First, copy `.env.example` to `.env` and set the appropriate environment variables (annotated with TODOs).

### Testing (Mainnet Forks)

1. Start anvil: two instances required, one for L1, and one for L2

```bash
# 1.1 start L1 (ethereum mainnet) anvil - NOTE: using port 8001 for L1
anvil --fork-url=mainnet --chain-id 1 --port 8001 --fork-block-number 19370366

# 1.2 start L2 (polygon zkevm) anvil - NOTE: using port 8101 for L2
anvil --fork-url=polygon_zkevm --chain-id 1101 --port 8101 --fork-block-number 10484909
```

2. Run the tests

```bash
forge test -vvvvv
```

or

```
forge test -vvvvv --match-contract NativeConverter
forge test -vvvvv --match-contract QuickSwap
forge test -vvvvv --match-contract KEOM
```

NOTE: `testBridgeFromL2AndCallL1Uniswap` might fail due to exchange rates, if you're not forking the expected block number. You can manually change the expected exchange rate in `ZkEVM2ETHMainnet.t.sol#L124`.

### Deployment

**NOTE: BridgeExtension (proxy) must be deployed to the same address in all chains**

setup the `DEPLOYER_PRIVATE_KEY`, `ADDRESS_PROXY_ADMIN`, `ADDRESS_LXLY_BRIDGE` and run

```
export RPC=
forge script script/DeployInitBridgeAndCall.s.sol:DeployInitBridgeAndCall --rpc-url ${RPC} -vvvvv --legacy --broadcast
```

## Audit

https://github.com/agglayer/lxly-bridge-and-call/tree/main/audit

## Future Work

- create easier interfaces for bridging assets (gas token, lx weth, erc20)
- helper claimBridgeAndCall function
- ethers/viem example calling bridgeAndCall

## Relevant Information

- [Demos Repository](https://github.com/AggLayer/lxly-bridge-and-call-demos/)

- [Bridge Asset Scenarios](https://docs.google.com/spreadsheets/d/1lBktJ5HSGwVXTzxm-eWCVhPGJKF22YvM59VaQBGLHMY)

![gm](./bridge-and-call.excalidraw.png)
