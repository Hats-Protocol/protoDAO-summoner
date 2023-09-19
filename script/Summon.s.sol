// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Script, console2 } from "forge-std/Script.sol";
import { HatsOnboardingShaman } from "hats-baal-shamans/src/HatsOnboardingShaman.sol";
import { IBaal } from "../lib/hats-baal-shamans/lib/baal/contracts/interfaces/IBaal.sol";
import { IBaalSummoner } from "../lib/hats-baal-shamans/lib/baal/contracts/interfaces/IBaalSummoner.sol";
import { BaalAdvTokenSummoner } from
  "../lib/hats-baal-shamans/lib/baal/contracts/higherOrderFactories/BaalAdvTokenSummoner.sol";
import { HatsModuleFactory } from "../lib/hats-baal-shamans/lib/hats-module/src/HatsModuleFactory.sol";
import {
  HatsModuleFactory,
  deployModuleInstance
} from "../lib/hats-baal-shamans/lib/hats-module/src/utils/DeployFunctions.sol";

contract SummonProtoDAO is Script {
  uint256 internal constant SALT_NONCE = 1; // change this with every new deploy

  HatsOnboardingShaman public shamanInstance;
  address public predictedShamanAddress;
  IBaal public baal;
  HatsModuleFactory public factory = HatsModuleFactory(0xfE661c01891172046feE16D3a57c3Cf456729efA);
  BaalAdvTokenSummoner public summoner = BaalAdvTokenSummoner(0xb0c5c96c3d21c1d58B98a5366dF0Af7AfcD94F95); // goerli
  // BaalAdvTokenSummoner public summoner = BaalAdvTokenSummoner(0x84561C97156a128662B62952890469214FDC87bf); //
  // optimism
  address public zodiacFactory = 0x00000000000DC7F163742Eb4aBEf650037b1f588;
  address public shamanImplementation = 0x21fD6DD770140ea847BE368237a3895131456A5b;
  uint256 public stewardHat =
    4_852_790_811_469_531_595_076_959_935_169_664_950_015_519_908_157_371_810_438_079_716_524_032;
  uint256 ownerHat = 4_852_790_400_087_115_163_040_062_715_663_533_521_254_685_996_057_303_046_598_649_844_858_880;
  uint256 public startingShares = 100 ether;
  string public shareName = "Proto Voting Rep";
  string public shareSymbol = "pvREP";
  string public lootName = "Proto Rep";
  string public lootSymbol = "pREP";
  address[] summoners = [0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4, 0xA7a5A2745f10D5C23d75a6fd228A408cEDe1CAE5];
  uint256[] summonerShares = [startingShares, startingShares];
  uint256[] summonerLoot = [0, 0];
  uint32 public voting = 3 minutes;
  uint32 public grace = 1 minutes;
  uint256 public newOffering = 0;
  uint256 public quorum = 0;
  uint256 public sponsor = 100 ether;
  uint256 public minRetention = 66;

  bytes public otherImmutableArgs;
  bytes public initData;

  function deployInstance(address _baal, uint256 _memberHat, uint256 _ownerHat, uint256 _startingShares)
    public
    returns (HatsOnboardingShaman)
  {
    // encode the other immutable args as packed bytes
    otherImmutableArgs = abi.encodePacked(_baal, _ownerHat);
    // encoded the initData as unpacked bytes -- for HatsOnboardingShaman, we just need any non-empty bytes
    initData = abi.encode(_startingShares);
    // deploy the instance
    return HatsOnboardingShaman(
      deployModuleInstance(factory, shamanImplementation, _memberHat, otherImmutableArgs, initData)
    );
  }

  function deployBaalWithConfig() public {
    // encode the token minting  params
    bytes memory mintParams = abi.encode(summoners, summonerShares, summonerLoot);

    // encode the token deployment params
    bytes memory tokenParams = abi.encode(shareName, shareSymbol, lootName, lootSymbol, false, false);

    bytes[] memory initializationActions = new bytes[](2);

    // encode the action to set the shaman
    address[] memory shamans = new address[](1);
    uint256[] memory permissions = new uint256[](1);
    shamans[0] = predictedShamanAddress;
    permissions[0] = 2; // manager only
    initializationActions[0] = abi.encodeCall(IBaal.setShamans, (shamans, permissions));

    // encode the action to set the governance config
    bytes memory governanceConfig = abi.encode(voting, grace, newOffering, quorum, sponsor, minRetention);
    initializationActions[1] = abi.encodeCall(IBaal.setGovernanceConfig, governanceConfig);

    // deploy the baal
    summoner.summonBaalFromReferrer({
      _safeAddr: address(0),
      _forwarderAddr: address(0),
      _saltNonce: SALT_NONCE,
      initializationMintParams: mintParams,
      initializationTokenParams: tokenParams,
      postInitializationActions: initializationActions
    });
  }

  /// @dev props to @santteegt
  function predictBaalAddress() public view returns (address baalAddress) {
    address template = IBaalSummoner(summoner._baalSummoner()).template();
    bytes memory initializer = abi.encodeWithSignature("avatar()");

    bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), SALT_NONCE));

    // This is how ModuleProxyFactory works
    bytes memory deployment =
    //solhint-disable-next-line max-line-length
     abi.encodePacked(hex"602d8060093d393df3363d3d373d3d3d363d73", template, hex"5af43d82803e903d91602b57fd5bf3");

    bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), zodiacFactory, salt, keccak256(deployment)));

    // NOTE: cast last 20 bytes of hash to address
    baalAddress = address(uint160(uint256(hash)));
  }

  /// @dev Set up the deployer via their private key from the environment
  function deployer() public returns (address) {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    return vm.rememberKey(privKey);
  }

  /// @dev Deploy the contract to a deterministic address via forge's create2 deployer factory.
  function run() public virtual {
    vm.startBroadcast(deployer());

    /* 
    protoDAO summoning steps
    1. predict the address of a baal
    2. predict the shaman address with the baal address as a param
    3. deploy the baal via the advanced token summoner, with the shaman address as a param
    4. deploy the hats onboarding shaman
    */

    // predict the baal address
    address predictedBaalAddress = predictBaalAddress();

    // deploy the shaman address
    // predict the shaman's address via the hats module factory
    predictedShamanAddress =
      factory.getHatsModuleAddress(shamanImplementation, stewardHat, abi.encodePacked(predictedBaalAddress, ownerHat));

    // deploy the baal
    deployBaalWithConfig();

    // deploy the shaman
    shamanInstance = deployInstance(predictedBaalAddress, stewardHat, ownerHat, startingShares);

    vm.stopBroadcast();

    console2.log("shaman", address(shamanInstance));
    console2.log("baal predicted", predictedBaalAddress);
    baal = shamanInstance.BAAL();
    console2.log("baal deployed", address(baal));
    console2.log("shaman perms", baal.shamans(address(shamanInstance)));
    console2.log("voting", baal.votingPeriod());
    console2.log("grace", baal.gracePeriod());
  }
}

/* FORGE CLI COMMANDS

## A. Simulate the deployment locally
forge script script/Summon.s.sol -f mainnet

## B. Deploy to real network and verify on etherscan
forge script script/Summon.s.sol -f mainnet --broadcast --verify

## C. Fix verification issues (replace values in curly braces with the actual values)
forge verify-contract --chain-id 1 --num-of-optimizations 1000000 --watch --constructor-args $(cast abi-encode \
 "constructor({args})" "{arg1}" "{arg2}" "{argN}" ) \ 
 --compiler-version v0.8.19 {deploymentAddress} \
 src/{Counter}.sol:{Counter} --etherscan-api-key $ETHERSCAN_KEY

*/
