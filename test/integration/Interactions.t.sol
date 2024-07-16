// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "../../script/Interactions.s.sol";

contract InteractionsTest is Test, CodeConstants {
    Raffle raffle;
    HelperConfig helperConfig;

    function setUp() external {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
    }

    function testCreateFundAndAddConsumerToSubscription() public {
        CreateSubscription createSubscription = new CreateSubscription();
        (uint256 subId, address vrfCoordinator) = createSubscription
            .createSubscriptionUsingConfig();

        address linkToken = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;

        FundSubscription fundSubscription = new FundSubscription();
        fundSubscription.fundSubscription(
            vrfCoordinator,
            subId,
            linkToken,
            account
        );

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(raffle),
            vrfCoordinator,
            subId,
            account
        );
    }
}
