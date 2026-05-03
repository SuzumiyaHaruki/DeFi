// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeFi {
    struct User {
        address addr;
        uint256 balance;
        bool exist;
    }

    uint256 public totalDeposits;
    address public owner;

    User[] public users;
    mapping(address => bool) public isAdmin;
    mapping(address => User) public map;

    IERC20 public token; // 可选 ERC20 代币，用于分红
    bool public yieldDistributionActive;
    uint256 public yieldCursor;
    uint256 public yieldSnapshot;
    uint256 public depositSnapshot;
    uint256 public distributedYield;

    constructor(IERC20 _token) {
        owner = msg.sender;
        isAdmin[owner] = true;
        token = _token;

        // 初始化 owner
        User memory temp = User({addr: owner, balance: 0, exist: true});
        map[owner] = temp;
        users.push(temp);
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyOwner() internal view {
        require(msg.sender == owner, "Only owner can use this function!");
    }

    function _onlyAdmin() internal view {
        require(isAdmin[msg.sender], "Only admin can use this function!");
    }

    event DepositMade(address indexed user, uint256 amount);
    event WithdrawalMade(address indexed user, uint256 amount);
    event TransferMade(address indexed from, address indexed to, uint256 amount);
    event YieldDistributionStarted(uint256 totalYield);
    event YieldDistributed(uint256 totalYield);

    function deposit() public payable {
        require(!yieldDistributionActive, "Yield distribution active");

        if (!map[msg.sender].exist) {
            User memory temp = User({addr: msg.sender, balance: 0, exist: true});
            map[msg.sender] = temp;
            users.push(temp);
        }
        // 以 wei 为单位进行存款
        uint256 value = msg.value;
        map[msg.sender].balance += value;
        totalDeposits += value;
        emit DepositMade(msg.sender, value);
    }

    function withdraw(uint256 value) public {
        require(!yieldDistributionActive, "Yield distribution active");
        require(map[msg.sender].balance >= value, "Insufficient balance");

        map[msg.sender].balance -= value;
        totalDeposits -= value;

        // Update accounting before the external call to avoid reentrancy issues.
        (bool sent,) = msg.sender.call{value: value}("");
        require(sent, "Transfer failed");

        emit WithdrawalMade(msg.sender, value);
    }

    function transfer(address to, uint256 value) public {
        require(!yieldDistributionActive, "Yield distribution active");
        require(to != address(0), "Invalid recipient");
        require(map[msg.sender].balance >= value, "Insufficient balance");

        map[msg.sender].balance -= value;

        if (!map[to].exist) {
            map[to] = User({addr: to, balance: 0, exist: true});
            users.push(map[to]);
        }
        map[to].balance += value;

        emit TransferMade(msg.sender, to, value);
    }

    function setAdmin(address addr) public onlyOwner {
        require(addr != address(0), "Invalid admin");

        isAdmin[addr] = true;
        if (!map[addr].exist) {
            map[addr] = User({addr: addr, balance: 0, exist: true});
            users.push(map[addr]);
        }
    }

    function deleteAdmin(address addr) public onlyOwner {
        isAdmin[addr] = false;
    }

    function startYieldDistribution() public onlyAdmin {
        require(!yieldDistributionActive, "Yield distribution active");
        require(totalDeposits > 0, "No deposits to distribute");

        uint256 totalYield = token.balanceOf(address(this));
        require(totalYield > 0, "No yield token to distribute");

        yieldDistributionActive = true;
        yieldCursor = 0;
        yieldSnapshot = totalYield;
        depositSnapshot = totalDeposits;
        distributedYield = 0;

        emit YieldDistributionStarted(totalYield);
    }

    function distributeYield(uint256 maxUsers) public onlyAdmin {
        require(yieldDistributionActive, "No active yield distribution");
        require(maxUsers > 0, "Invalid max users");

        uint256 end = yieldCursor + maxUsers;
        if (end > users.length) {
            end = users.length;
        }

        for (uint256 i = yieldCursor; i < end; i++) {
            User storage u = map[users[i].addr];

            if (u.balance > 0) {
                uint256 share = (u.balance * yieldSnapshot) / depositSnapshot;

                if (share > 0) {
                    distributedYield += share;

                    bool success = token.transfer(u.addr, share);
                    require(success, "Token transfer failed");
                }
            }
        }

        yieldCursor = end;

        if (yieldCursor == users.length) {
            yieldDistributionActive = false;
            emit YieldDistributed(distributedYield);
        }
    }
}
