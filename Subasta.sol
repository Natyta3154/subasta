// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Auction - Auction contract with minimum increments, time extensions, and commission.
/// @author Hernan
contract Auction {
    address public immutable owner;
    address public winner;
    uint public winningBid;
    uint public auctionStartTime;
    uint public auctionEndTime;
    bool public finalized;
    bool public commissionWithdrawn;

    uint public constant EXTENSION_TIME = 10 minutes;
    uint public constant MIN_GLOBAL_INCREMENT_PERCENTAGE = 5; // +5%
    uint public constant COMMISSION_PERCENTAGE = 2; // 2% commission
    uint public constant MIN_OWN_BID_INCREMENT_PERCENTAGE = 1; // +1% on own bid

    struct ParticipantBid {
        uint currentAmount;
        uint totalDeposited;
        bool exists;
    }

    mapping(address => ParticipantBid) public bids;
    address[] public bidderList;

    // Events
    event NewBid(address indexed bidder, uint amount);
    event AuctionFinalized(address indexed winner, uint winningAmount);
    event ExcessWithdrawn(address indexed participant, uint amount);
    event LoserRefunded(address indexed loser, uint refundedAmount);

    // Modifiers
    modifier onlyWhileActive() {
        require(block.timestamp < auctionEndTime, "ERR_ENDED");
        require(!finalized, "ERR_FINALIZED");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "ERR_NOT_OWNER");
        _;
    }

    /// @notice Initializes the auction with a duration in seconds.
    /// @param _durationSeconds Duration of the auction in seconds.
    constructor(uint _durationSeconds) {
        owner = msg.sender;
        auctionStartTime = block.timestamp;
        auctionEndTime = auctionStartTime + _durationSeconds;
    }

    /// @notice Places a valid bid with minimum increments.
    /// @dev Extends auction if less than 10 minutes remain.
    /// @dev Requires auction to be active and not finalized.
    /// @dev The sent value must meet minimum increments.
    function bid() external payable onlyWhileActive {
        require(msg.value > 0, "ERR_NO_ETH");

        ParticipantBid storage userBid = bids[msg.sender];
        uint newTotalBid = msg.value;

        // Minimum increment on own previous bid
        if (userBid.exists && userBid.currentAmount > 0) {
            uint minOwnAmount = userBid.currentAmount + (userBid.currentAmount * MIN_OWN_BID_INCREMENT_PERCENTAGE) / 100;
            require(newTotalBid >= minOwnAmount, "ERR_LOW_SELF_INC");
        }

        // Minimum increment over global winning bid
        if (winningBid == 0) {
            require(newTotalBid > 0, "ERR_FIRST_BID_ZERO");
        } else {
            uint minGlobalAmount = winningBid + (winningBid * MIN_GLOBAL_INCREMENT_PERCENTAGE) / 100;
            require(newTotalBid >= minGlobalAmount, "ERR_LOW_GLOBAL_INC");
        }

        // Register new bidder if needed
        if (!userBid.exists) {
            bidderList.push(msg.sender);
            userBid.exists = true;
        }

        userBid.totalDeposited += msg.value;
        userBid.currentAmount = newTotalBid;

        // Update winner if this is highest bid
        if (newTotalBid > winningBid) {
            winningBid = newTotalBid;
            winner = msg.sender;
        }

        // Extend auction if less than EXTENSION_TIME left
        if (auctionEndTime - block.timestamp <= EXTENSION_TIME) {
            auctionEndTime += EXTENSION_TIME;
        }

        emit NewBid(msg.sender, newTotalBid);
    }

    /// @notice Returns remaining time of the auction in seconds.
    /// @return uint Time left in seconds, 0 if auction ended.
    function timeLeft() external view returns (uint) {
        if (block.timestamp >= auctionEndTime) {
            return 0;
        }
        return auctionEndTime - block.timestamp;
    }

    /// @notice Withdraw excess deposit or refund for losers after auction finalized.
    /// @dev Excess = total deposited - current active bid.
    /// @dev Losers pay 2% commission on refund.
    function withdrawExcess() external {
        ParticipantBid storage userBid = bids[msg.sender];

        uint totalDeposited = userBid.totalDeposited;
        uint currentAmount = userBid.currentAmount;

        require(totalDeposited > 0, "ERR_NO_DEP");

        uint amountToWithdraw;

        if (finalized && msg.sender != winner) {
            uint commission = (totalDeposited * COMMISSION_PERCENTAGE) / 100;
            amountToWithdraw = totalDeposited - commission;

            userBid.totalDeposited = 0;
            userBid.currentAmount = 0;

            emit LoserRefunded(msg.sender, amountToWithdraw);
        } else {
            require(totalDeposited > currentAmount, "ERR_NOT_EXCESS");
            amountToWithdraw = totalDeposited - currentAmount;

            userBid.totalDeposited = totalDeposited - amountToWithdraw;

            emit ExcessWithdrawn(msg.sender, amountToWithdraw);
        }

        (bool success, ) = payable(msg.sender).call{value: amountToWithdraw}("");
        require(success, "ERR_SEND_FAIL");
    }

    /// @notice Allows withdrawing part of the excess deposit over the active bid.
    /// @param amount Amount in wei to withdraw from excess.
    /// @dev Can only withdraw up to the available excess, not touching active bid.
    function withdrawPartial(uint amount) external {
        ParticipantBid storage userBid = bids[msg.sender];
        require(userBid.totalDeposited > 0, "ERR_NO_DEP");
        require(amount > 0, "ERR_INV_AMT");
        require(userBid.totalDeposited > userBid.currentAmount, "ERR_NO_EXCESS");

        uint excess = userBid.totalDeposited - userBid.currentAmount;
        require(amount <= excess, "ERR_TOO_MUCH");

        userBid.totalDeposited -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ERR_SEND_FAIL");

        emit ExcessWithdrawn(msg.sender, amount);
    }

    /// @notice Finalizes the auction. Only the owner can call this.
    /// @dev Can only be called after auction ended and if not already finalized.
    function finalizeAuction() external onlyOwner {
        require(block.timestamp >= auctionEndTime, "ERR_NOT_ENDED");
        require(!finalized, "ERR_ALREADY_FINALIZED");

        finalized = true;
        emit AuctionFinalized(winner, winningBid);
    }

    /// @notice Returns the winner and winning bid.
    /// @dev Available only after auction is finalized.
    /// @return winnerAddress The address of the winner.
    /// @return winningAmount The amount of the winning bid.
    function showWinner() external view returns (address winnerAddress, uint winningAmount) {
        require(finalized, "ERR_NOT_FINALIZED");
        return (winner, winningBid);
    }

    /// @notice Returns list of bidders and their current bids.
    /// @return bidders List of bidder addresses.
    /// @return amounts List of corresponding current bid amounts.
    function showBids() external view returns (address[] memory bidders, uint[] memory amounts) {
        uint len = bidderList.length;
        uint[] memory currentBids = new uint[](len);
        for (uint i = 0; i < len; i++) {
            currentBids[i] = bids[bidderList[i]].currentAmount;
        }
        return (bidderList, currentBids);
    }

    /// @notice Allows owner to withdraw 2% commission on the winning bid.
    /// @dev Only once, and only after auction finalized.
    function withdrawCommission() external onlyOwner {
        require(finalized, "ERR_NOT_FINALIZED");
        require(winningBid > 0, "ERR_NO_WINBID");
        require(!commissionWithdrawn, "ERR_COMM_TAKEN");

        uint commission = (winningBid * COMMISSION_PERCENTAGE) / 100;
        require(commission > 0, "ERR_ZERO_COMM");

        commissionWithdrawn = true;
        (bool success, ) = payable(owner).call{value: commission}("");
        require(success, "ERR_SEND_FAIL");
    }

    /// @notice Refunds all losers, subtracting commission.
    /// @dev Only owner can call after auction finalized.
    function refundAllLosers() external onlyOwner {
        require(finalized, "ERR_NOT_FINALIZED");

        uint len = bidderList.length;
        for (uint i = 0; i < len; i++) {
            address bidder = bidderList[i];

            if (bidder == winner) {
                continue;
            }

            ParticipantBid storage bidInfo = bids[bidder];

            if (bidInfo.totalDeposited > 0) {
                uint refundAmount = bidInfo.totalDeposited - (bidInfo.totalDeposited * COMMISSION_PERCENTAGE) / 100;

                bidInfo.totalDeposited = 0;
                bidInfo.currentAmount = 0;

                (bool success, ) = payable(bidder).call{value: refundAmount}("");
                require(success, "ERR_SEND_FAIL");

                emit LoserRefunded(bidder, refundAmount);
            }
        }
    }

    /// @notice Emergency function to withdraw all ETH from the contract.
/// @dev Only the owner can call this function.
/// @dev Use only in case of emergency to recover stuck ETH.
function emergencyWithdraw() external onlyOwner {
    uint contractBalance = address(this).balance;
    require(contractBalance > 0, "ERR_NO_BALANCE");

    (bool success, ) = payable(owner).call{value: contractBalance}("");
    require(success, "ERR_SEND_FAIL");
}
}
