// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/*
Fork SushiSwap’s SushiBar contract and implement following featuresStaking:
> Time lock after staking:
> 2 days - 0% can be unstaked - 172800 seconds
> 2-4 days - 25% can be unstaked - 345600 sec
> 4-6 days - 50% can be unstaked - 518400 sec
> 6-8 days - 75% can be unstaked - 691200 sec
> After 8 days - 100% can be unstaked.This will work like a high tax though.
> 0-2 days - locked
> 2-4 days - 75% tax
> 4-6 days - 50% tax
> 6-8 days - 25% tax
> After 8 days, 0% tax.
> The tokens received on tax will go back into rewards pool.
*/
// SushiBar is the coolest bar in town. You come in with some Sushi, and leave with more! The longer you stay, the more Sushi you get.
//
// This contract handles swapping to and from xSushi, SushiSwap's staking token.
contract SushiBar is ERC20("SushiBar", "xSUSHI"){
    IERC20 public sushi;

    // Define the Sushi token contract
    constructor(IERC20 _sushi) {
        sushi = _sushi;
    }

    // keeps track of entry time of a user's skate
    mapping (address => uint256) entryTime;

    // calculates staking time by using entryTime mapping
    function stakeTime(address _user) internal view returns(uint256) {
        uint _stakeTime = block.timestamp - entryTime[_user];
        return _stakeTime;
    }

    // keeps track of xSUSHI tokens for addresses - can be used in timelock and early unstake scenarios
    mapping (address => uint256) tokens ;

    // keeps track of sushi token rewards pool
    mapping (IERC20 => uint256) rewards ;

    function entry() internal {
        entryTime[msg.sender] = block.timestamp;
    }

    // Enter the bar. Pay some SUSHIs. Earn some shares.
    // Locks Sushi and mints xSushi
    function enter(uint256 _amount) public {
        // Gets the amount of Sushi locked in the contract
        uint256 totalSushi = sushi.balanceOf(address(this));
        // Gets the amount of xSushi in existence
        uint256 totalShares = totalSupply();
        // If no xSushi exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalSushi == 0) {
            _mint(msg.sender, _amount);
            tokens[msg.sender] = _amount;
        } else {
        // Calculate and mint the amount of xSushi the Sushi is worth. The ratio will change overtime, as xSushi is burned/minted and Sushi deposited + gained from fees / withdrawn.  
            uint256 what = _amount* totalShares / totalSushi;
            _mint(msg.sender, what);
            tokens[msg.sender] += what ;
        }
        entry();
        // Lock the Sushi in the contract
        sushi.transferFrom(msg.sender, address(this), _amount);
    }

    modifier unstakeAmount (uint amount){
        uint _stakeTime = stakeTime(msg.sender);
        require(_stakeTime > 2 days, "can not unstake before 2 days");
        if (_stakeTime > 2 days && _stakeTime <= 4 days) {
            require (amount <= tokens[msg.sender] * 25/100, "can only unstake 25% before 4 days");
        } else if (_stakeTime > 4 days && _stakeTime <= 6 days) {
            require (amount <= tokens[msg.sender] * 50/100, "can only unstake 50% before 6 days");
        } else if (_stakeTime > 6 days && _stakeTime <= 8 days) {
            require (amount <= tokens[msg.sender] * 75/100, "can only unstake 75% before 8 days");
        } else {
            require (amount <= tokens[msg.sender]);
        }
        _;
    }
    address public rewardsPool;
    // Leave the bar. Claim back your SUSHIs.
    // Unlocks the staked + gained Sushi and burns xSushi
    function leave(uint256 _share) public unstakeAmount(_share) {
        uint a = stakeTime(msg.sender);
        // Gets the amount of xSushi in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Sushi the xSushi is worth
        uint256 what = _share * sushi.balanceOf(address(this))/totalShares;
        _burn(msg.sender, _share);
        
        tokens[msg.sender] -= _share ;

        // amount user gets after taxes (if any tax is applicable)
        uint amountToSend;
        
        if (a <= 4 days) {
            // 75% goes to tax & user recieves 25% - 75% tax before 4 days
            amountToSend = what * 25/100 ;
        } else if (a > 4 days && a <= 6 days) {
            // 50% goes to tax & user recieves 50% - 50% tax 4-6 days
            amountToSend = what * 50/100 ;
        } else if (a > 6 days && a <= 8 days) {
            // 25% goes to tax & user recieves 75% - 25% tax 6-8 days
            amountToSend = what * 75/100 ;
        } else if (a > 8 days) {
            // No tax after 8 days 
            amountToSend = what ;
        }
        
        // taxed amount which goes to Rewards pool 
        uint amountToPool = what - amountToSend;
        
        // user recieves amount & the remaining goes to rewards 
        bool sent;
        (sent, ) = payable(msg.sender).call{value: amountToSend} ("");
        // tokens received on tax will go to rewards pool
        rewards[sushi] += amountToPool;
    }

}