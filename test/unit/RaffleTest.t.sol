// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 s_entranceFee;
    uint256 s_interval;
    address s_vrfCoordinator;
    bytes32 s_gasLane;
    uint256 s_subscriptionId;
    uint32 s_callbackGasLimit;

    uint256 private constant STARTING_PLAYER_BALANCE = 10 ether;
    address private immutable i_player = makeAddr("player");

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed player);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployRaffle();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        s_entranceFee = config.entranceFee;
        s_interval = config.interval;
        s_vrfCoordinator = config.vrfCoordinator;
        s_gasLane = config.gasLane;
        s_subscriptionId = config.subscriptionId;
        s_callbackGasLimit = config.callbackGasLimit;

        vm.deal(i_player, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertWhenYouDontPayEnough() public {
        vm.prank(i_player);

        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle{value: 0}();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        vm.prank(i_player);

        raffle.enterRaffle{value: s_entranceFee}();
        address playerRecorded = raffle.getPlayer(0);

        assert(i_player == playerRecorded);
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.prank(i_player);

        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(i_player);

        raffle.enterRaffle{value: s_entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        vm.prank(i_player);
        raffle.enterRaffle{value: s_entranceFee}();
        vm.warp(block.timestamp + s_interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(i_player);
        raffle.enterRaffle{value: s_entranceFee}();
    }
}
