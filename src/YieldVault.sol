// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract YieldVault is ERC4626, Ownable, Pausable {
    using SafeERC20 for IERC20;

    error InvalidAsset();
    error ZeroAssets();

    event YieldAdded(address indexed caller, uint256 assets);

    constructor(IERC20 asset_, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC4626(asset_)
        Ownable(msg.sender)
    {
        if (address(asset_) == address(0)) {
            revert InvalidAsset();
        }
    }

    // owner 可在紧急情况下暂停存款、铸造、提现和赎回。
    function pause() external onlyOwner {
        _pause();
    }

    // owner 可恢复金库操作。
    function unpause() external onlyOwner {
        _unpause();
    }

    // owner 注入底层资产但不铸造份额，用来模拟策略收益，已有用户的每份 share 会变得更值钱。
    function addYield(uint256 assets) external onlyOwner {
        if (assets == 0) {
            revert ZeroAssets();
        }

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        emit YieldAdded(msg.sender, assets);
    }

    // 查询 1 个份额当前能兑换多少底层资产。
    function pricePerShare() external view returns (uint256) {
        return convertToAssets(10 ** decimals());
    }

    // 查询 receiver 当前最多可以存入多少资产。暂停时返回 0，表示暂不可存款。
    // 未暂停时复用 OpenZeppelin ERC4626 的默认上限逻辑。
    function maxDeposit(address receiver) public view override returns (uint256) {
        return paused() ? 0 : super.maxDeposit(receiver);
    }

    // 查询 receiver 当前最多可以铸造多少份额。暂停时返回 0，表示暂不可铸造。
    // 未暂停时复用 OpenZeppelin ERC4626 的默认上限逻辑。
    function maxMint(address receiver) public view override returns (uint256) {
        return paused() ? 0 : super.maxMint(receiver);
    }

    // 查询 owner 当前最多可以提取多少资产。暂停时返回 0。
    function maxWithdraw(address owner) public view override returns (uint256) {
        return paused() ? 0 : super.maxWithdraw(owner);
    }

    // 查询 owner 当前最多可以赎回多少份额。暂停时返回 0。
    function maxRedeem(address owner) public view override returns (uint256) {
        return paused() ? 0 : super.maxRedeem(owner);
    }

    // 只增加暂停检查，实际资产转入和份额铸造交给 ERC4626。
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        whenNotPaused
    {
        super._deposit(caller, receiver, assets, shares);
    }

    // 只增加暂停检查，实际份额销毁和资产转出交给 ERC4626。
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        whenNotPaused
    {
        super._withdraw(caller, receiver, owner, assets, shares);
    }
}
