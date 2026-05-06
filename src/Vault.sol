// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Vault is ERC20, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    error ZeroAssets();
    error ZeroShares();
    error InvalidReceiver();
    error InvalidOwner();

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event YieldAdded(address indexed caller, uint256 assets);

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (address(asset_) == address(0)) {
            revert InvalidReceiver();
        }

        asset = asset_;
    }

    // 返回合约中存储的资产总量
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // 返回给定数量的资产（asserts）可以兑换成多少份额（shares）
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        // 如果当前没有任何份额（supply == 0），则每个资产兑换成一个份额；否则按照当前的总资产和总份额比例进行兑换
        return supply == 0 ? assets : Math.mulDiv(assets, supply, totalAssets());
    }

    // 返回给定数量的份额（shares）可以兑换成多少资产（asserts）
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        // 如果当前没有任何份额（supply == 0），则每个份额兑换成一个资产；否则按照当前的总资产和总份额比例进行兑换
        return supply == 0 ? shares : Math.mulDiv(shares, totalAssets(), supply);
    }

    // 预查询给定数量的资产（assets）可以兑换成多少份额（shares），不进行实际兑换
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    // 预查询铸造给定数量的份额（shares）需要多少资产（assets），不进行实际铸造
    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        // 这里会使用向上取整的方式计算需要的资产数量，以确保用户至少提供足够的资产来铸造所需的份额
        return supply == 0 ? shares : Math.mulDiv(shares, totalAssets(), supply, Math.Rounding.Ceil);
    }

    // 预查询赎回给定数量的资产（assets）需要多少份额（shares），不进行实际赎回
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : Math.mulDiv(assets, supply, totalAssets(), Math.Rounding.Ceil);
    }

    // 预查询给定数量的份额（shares）可以赎回多少资产（assets），不进行实际赎回
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    // 查询 receiver 当前最多可以存入多少资产。暂停时返回 0，表示暂不可存款。
    // 实际上相当于查询是否 paused。
    function maxDeposit(address) public view returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    // 查询 receiver 当前最多可以铸造多少份额。暂停时返回 0，表示暂不可铸造。
    // 实际上相当于查询是否 paused。
    function maxMint(address) public view returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    // 查询 owner 当前最多可以提取多少资产。
    function maxWithdraw(address owner) public view returns (uint256) {
        return paused() ? 0 : convertToAssets(balanceOf(owner));
    }

    // 查询 owner 当前最多可以赎回多少份额。
    function maxRedeem(address owner) public view returns (uint256) {
        return paused() ? 0 : balanceOf(owner);
    }

    // 查询 1 个份额当前能兑换多少底层资产。
    function pricePerShare() external view returns (uint256) {
        return convertToAssets(10 ** decimals());
    }

    // owner 注入底层资产但不铸造份额，用来模拟策略收益，已有用户的每份 share 会变得更值钱。
    function addYield(uint256 assets) external onlyOwner {
        if (assets == 0) {
            revert ZeroAssets();
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);

        emit YieldAdded(msg.sender, assets);
    }

    // owner 可在紧急情况下暂停存款、铸造、提现和赎回。
    function pause() external onlyOwner {
        _pause();
    }

    // owner 可恢复金库操作。
    function unpause() external onlyOwner {
        _unpause();
    }

    // 用户存入一定数量的资产（assets），并将相应数量的份额（shares）铸造给接收者（receiver）
    function deposit(uint256 assets, address receiver) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets == 0) {
            revert ZeroAssets();
        }
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        shares = previewDeposit(assets);
        if (shares == 0) {
            revert ZeroShares();
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    // 用户铸造一定数量的份额（shares）并转移给接收者（receiver），将铸造所需的资产（assets）从调用者转移到合约
    function mint(uint256 shares, address receiver) external nonReentrant whenNotPaused returns (uint256 assets) {
        if (shares == 0) {
            revert ZeroShares();
        }
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        assets = previewMint(shares);
        if (assets == 0) {
            revert ZeroAssets();
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    // 用户提取一定数量的资产（assets），将相应数量的份额（shares）从所有者（owner）销毁，并将资产转移给接收者（receiver）
    function withdraw(uint256 assets, address receiver, address owner)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) {
            revert ZeroAssets();
        }
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }
        if (owner == address(0)) {
            revert InvalidOwner();
        }

        shares = previewWithdraw(assets);
        _spendAllowanceIfNeeded(owner, shares);
        _burn(owner, shares);
        asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    // 用户赎回一定数量的份额（shares），将相应数量的资产（assets）从合约转移给接收者（receiver），并将份额从所有者（owner）销毁
    function redeem(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) {
            revert ZeroShares();
        }
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }
        if (owner == address(0)) {
            revert InvalidOwner();
        }

        assets = previewRedeem(shares);
        if (assets == 0) {
            revert ZeroAssets();
        }

        _spendAllowanceIfNeeded(owner, shares);
        _burn(owner, shares);
        asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    // 如果调用者不是所有者（owner），则检查并消耗调用者对所有者的份额（shares）授权，以确保调用者有权代表所有者进行操作
    function _spendAllowanceIfNeeded(address owner, uint256 shares) internal {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
    }
}
