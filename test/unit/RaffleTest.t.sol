// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
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

    modifier playerEntered() {
        vm.prank(i_player);
        raffle.enterRaffle{value: s_entranceFee}();
        _;
    }

    modifier timePassed() {
        advanceTimeAndBlock();
        _;
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        s_entranceFee = config.entranceFee;
        s_interval = config.interval;
        s_vrfCoordinator = config.vrfCoordinator;
        s_gasLane = config.gasLane;
        s_subscriptionId = config.subscriptionId;
        s_callbackGasLimit = config.callbackGasLimit;

        vm.deal(i_player, STARTING_PLAYER_BALANCE);
    }

    /**
     * Enter Raffle
     */

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertWhenYouDontPayEnough() public {
        vm.prank(i_player);

        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle{value: 0}();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public playerEntered {
        address playerRecorded = raffle.getPlayer(0);

        assert(i_player == playerRecorded);
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.prank(i_player);

        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(i_player);

        raffle.enterRaffle{value: s_entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating()
        public
        playerEntered
        timePassed
    {
        raffle.performUpkeep("");

        // Act
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(i_player);
        raffle.enterRaffle{value: s_entranceFee}();
    }

    /**
     * Check Upkeep
     */
    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public timePassed {
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleIsNotOpen()
        public
        playerEntered
        timePassed
    {
        raffle.performUpkeep("");

        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed()
        public
        playerEntered
    {
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueIfWhenParametersAreGood()
        public
        playerEntered
        timePassed
    {
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        assert(upkeepNeeded);
    }

    /*
     * Perform Upkeep
     */

    function testIfPerformUpkeepCanOnlyRunIfUpkeepIsTrue()
        public
        playerEntered
        timePassed
    {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(i_player);
        raffle.enterRaffle{value: s_entranceFee}();
        currentBalance += s_entranceFee;
        numPlayers++;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        playerEntered
        timePassed
    {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    /*
     * FULFILLRANDOMWORDS
     */

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public playerEntered timePassed skipFork {
        // Arrange / Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(s_vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        skipFork
    {
        // Arrange
        uint160 additionalEntrance = 4;
        uint160 startingIndex = 1;
        address expectedWinner = address(2);
        for (
            uint160 i = startingIndex;
            i < startingIndex + additionalEntrance;
            i++
        ) {
            hoax(address(i), STARTING_PLAYER_BALANCE);
            raffle.enterRaffle{value: s_entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        advanceTimeAndBlock();
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(s_vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = s_entranceFee * additionalEntrance;

        console.log("Recent Winner: ", recentWinner);
        console.log("Expected Winner: ", expectedWinner);
        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }

    /* Private Functions */

    function advanceTimeAndBlock() private {
        vm.warp(block.timestamp + s_interval + 1);
        vm.roll(block.number + 1);
    }
}
