#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify-fuji.sh
# Re-verifies all contracts from the last Deploy.s.sol broadcast on Fuji
# using Routescan (the actual backend for testnet.snowtrace.io).
#
# Usage:
#   chmod +x script/verify-fuji.sh
#   ./script/verify-fuji.sh
# ---------------------------------------------------------------------------
# NOTE: No "set -e" — a transient network error on one contract should NOT
#       abort the rest. Each contract is attempted independently.

CHAIN=43113
RPC="https://api.avax-test.network/ext/bc/C/rpc"
VERIFIER_URL="https://api.routescan.io/v2/network/testnet/evm/43113/etherscan"
API_KEY="verifyContract"   # Routescan accepts any non-empty string

BASE_FLAGS="--chain $CHAIN
  --rpc-url $RPC
  --verifier etherscan
  --verifier-url $VERIFIER_URL
  --etherscan-api-key $API_KEY
  --via-ir
  --optimizer-runs 200
  --evm-version cancun"

PASS=0
FAIL=0

verify() {
  local label="$1"; local addr="$2"; shift 2
  echo ""
  echo ">>> $label"
  if forge verify-contract "$addr" $BASE_FLAGS "$@"; then
    echo "    OK"
    PASS=$((PASS + 1))
  else
    echo "    FAILED — re-run manually or retry the script"
    FAIL=$((FAIL + 1))
  fi
}

echo "======================================================"
echo "  Verifying contracts on Fuji via Routescan"
echo "======================================================"

# --- Implementations (1-4 already submitted but forge will say "already verified" — safe) ---
verify "1/9  ReferralRewards" \
  0xcd0661044DfD37AcD56E595cD549888e0E07EdDF \
  src/ReferralRewards.sol:ReferralRewards

verify "2/9  PersonalSavings" \
  0xc0Cf7f8F6a7966c6CAaA792835126f3c107a909D \
  src/PersonalSavings.sol:PersonalSavings

verify "3/9  CircleSavings" \
  0x3754319fA0Dd919D0724fa0C446eb363C9a36FF4 \
  src/CircleSavings.sol:CircleSavings

verify "4/9  Reputation" \
  0xdEe24CEbB7139C180063Fda56B87F19f4a7b6b2B \
  src/Reputation.sol:Reputation

verify "5/9  YieldVault" \
  0x476C8C48B01Be4e9CeD9760E0dD7bc4570B83B83 \
  src/mocks/YieldVault.sol:YieldVault \
  --constructor-args "$(cast abi-encode 'constructor(address,string,string)' \
    0xe033DDef5ef67Cbc7CeC24fe5C58eC06E9BfFD67 \
    'Yield Bearing USDT' \
    'yUSDT')"

# --- Proxies ---
verify "6/9  ReputationProxy" \
  0x26a606222894d22CDEA34F2D0Ca705e082e86372 \
  src/proxies/ReputationProxy.sol:ReputationProxy \
  --constructor-args "$(cast abi-encode 'constructor(address,address)' \
    0xdEe24CEbB7139C180063Fda56B87F19f4a7b6b2B \
    0x4781070885eA1E2Ec9aE46201703172c576cDA1A)"

verify "7/9  ReferralRewardsProxy" \
  0x4c252089abA090FF4306c899FD07ac6A21a56e7e \
  src/proxies/ReferralRewardsProxy.sol:ReferralRewardsProxy \
  --constructor-args "$(cast abi-encode 'constructor(address,address)' \
    0x33fFf7699D4871a6BF06EBD5e829111D783351a9 \
    0x4781070885eA1E2Ec9aE46201703172c576cDA1A)"

verify "8/9  PersonalSavingsProxy" \
  0x123bFf8D754b29772E1EfAD5B075F55600577DcD \
  src/proxies/PersonalSavingsProxy.sol:PersonalSavingsProxy

verify "9/9  CircleSavingsProxy" \
  0x6e222b5507F7554A163B37C4DfC6d62dE3077fA8 \
  src/proxies/CircleSavingsProxy.sol:CircleSavingsProxy

echo ""
echo "======================================================"
echo "  Summary: $PASS passed, $FAIL failed"
echo "  Check: https://testnet.snowtrace.io"
echo "======================================================"
