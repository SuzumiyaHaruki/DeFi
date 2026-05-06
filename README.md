# DeFi Yield Vault

这是一个基于 Foundry 编写的 Solidity DeFi 金库项目：

- `Vault.sol`：手写 ERC4626-style 金库，用于学习 shares/assets 兑换、preview 查询、赎回和收益注入的底层逻辑。
- `YieldVault.sol`：基于 OpenZeppelin `ERC4626` 的标准金库版本，更接近真实项目中的工程实践。

项目使用 ERC20 作为底层资产。用户存入底层资产后获得金库份额 shares；当 owner 向金库注入额外收益资产时，不会增发 shares，因此每份 share 可兑换的底层资产会增加。

## 项目定位

本项目用于 DeFi 金库协议的学习，重点展示：

- ERC4626 份额制金库的核心原理
- assets 与 shares 的双向换算
- deposit、mint、withdraw、redeem 四种标准金库操作
- 收益注入后 share price 上升的机制
- `Ownable`、`Pausable`、`ReentrancyGuard`、`SafeERC20` 等基础安全组件的使用
- 手写实现与 OpenZeppelin 标准实现之间的差异

## 合约说明

### Vault.sol

`Vault.sol` 是手写 ERC4626-style 版本，金库份额本身继承 `ERC20`。

它主要实现了：

- `totalAssets()`：查询金库当前持有的底层资产总量
- `convertToShares(assets)`：将资产数量换算为 shares
- `convertToAssets(shares)`：将 shares 数量换算为资产
- `previewDeposit(assets)`：预估存入资产可获得多少 shares
- `previewMint(shares)`：预估铸造指定 shares 需要多少资产
- `previewWithdraw(assets)`：预估提取指定资产需要销毁多少 shares
- `previewRedeem(shares)`：预估赎回指定 shares 可获得多少资产
- `maxDeposit()`、`maxMint()`、`maxWithdraw()`、`maxRedeem()`：查询当前最大可操作额度
- `deposit()`：存入指定资产并铸造 shares
- `mint()`：铸造指定 shares 并转入所需资产
- `withdraw()`：提取指定资产并销毁 shares
- `redeem()`：赎回指定 shares 并转出资产
- `addYield()`：owner 注入收益资产，不增发 shares
- `pricePerShare()`：查询 1 个完整 share 当前可兑换多少底层资产
- `pause()`、`unpause()`：owner 暂停或恢复金库存取款

这个版本的价值在于可以直接看到 ERC4626 核心公式：

```solidity
shares = assets * totalSupply / totalAssets
assets = shares * totalAssets / totalSupply
```

当金库没有任何 shares 时，采用 `1 asset = 1 share` 的初始兑换关系。

### YieldVault.sol

`YieldVault.sol` 是基于 OpenZeppelin `ERC4626` 的标准版本。

它不再手写核心兑换逻辑，而是复用 OpenZeppelin 已经实现好的：

- `totalAssets`
- `convertToShares`
- `convertToAssets`
- `previewDeposit`
- `previewMint`
- `previewWithdraw`
- `previewRedeem`
- `deposit`
- `mint`
- `withdraw`
- `redeem`

项目只在标准 ERC4626 基础上增加：

- `Ownable`：限制收益注入和暂停操作
- `Pausable`：紧急情况下暂停存款、铸造、提现和赎回
- `addYield()`：模拟策略收益或奖励注入
- `pricePerShare()`：方便前端或测试观察 share price
- `maxDeposit()`、`maxMint()`、`maxWithdraw()`、`maxRedeem()` override：暂停时返回 `0`


## 核心流程

### 存入资产

用户先对金库合约授权底层 ERC20 资产，然后调用：

```solidity
deposit(assets, receiver)
```

金库会从调用者转入 `assets` 数量的底层资产，并根据当前兑换比例给 `receiver` 铸造 shares。

### 铸造份额

用户也可以反过来指定想要获得多少 shares：

```solidity
mint(shares, receiver)
```

金库会计算铸造这些 shares 需要多少底层资产，并从调用者转入对应资产。

### 提取资产

用户指定想要取出多少底层资产：

```solidity
withdraw(assets, receiver, owner)
```

金库会计算需要销毁多少 shares，并把底层资产发送给 `receiver`。

如果调用者不是 `owner`，需要提前获得 `owner` 对 shares 的授权。

### 赎回份额

用户也可以指定销毁多少 shares：

```solidity
redeem(shares, receiver, owner)
```

金库会根据当前兑换比例把对应底层资产发送给 `receiver`。

### 注入收益

owner 可以调用：

```solidity
addYield(assets)
```

该函数只向金库转入底层资产，不铸造新的 shares。这样总资产增加、总 shares 不变，每份 share 可兑换的资产数量会上升。

示例：

```txt
Alice 存入 100 asset，获得 100 shares
owner 注入 20 asset 收益
金库总资产变为 120 asset，总 shares 仍为 100
Alice 的 100 shares 现在可赎回约 120 asset
```

## Vault.sol 与 YieldVault.sol 对比

| 对比项 | Vault.sol | YieldVault.sol |
|---|---|---|
| 定位 | 手写 ERC4626-style 学习版 | OpenZeppelin ERC4626 标准版 |
| shares token | 继承 `ERC20` 手动实现 | `ERC4626` 内部继承 `ERC20` |
| 资产/份额换算 | 手写 `convertToShares` / `convertToAssets` | 复用 OpenZeppelin ERC4626 |
| deposit/mint/withdraw/redeem | 手写完整流程 | 复用 ERC4626 流程 |
| SafeERC20 | 使用 | ERC4626 内部使用，`addYield` 中也使用 |
| ReentrancyGuard | 显式使用 | 未额外添加，依赖 OZ ERC4626 的执行顺序 |
| Pausable | 使用 | 使用 |
| addYield | 手写 | 手写 |
| pricePerShare | 手写 | 手写 |
| 适合用途 | 理解底层机制 | 简历主版本、工程实践展示 |

## 安全设计

当前项目包含以下基础安全设计：

- 使用 `SafeERC20` 兼容不规范 ERC20 返回值
- 使用 `Ownable` 限制收益注入和暂停权限
- 使用 `Pausable` 提供紧急暂停能力
- `Vault.sol` 使用 `ReentrancyGuard` 防止重入调用
- 提现和赎回前先销毁 shares，再转出底层资产
- 存款、铸造、提现、赎回均检查零数量或无效接收地址
- 暂停时 `maxDeposit`、`maxMint`、`maxWithdraw`、`maxRedeem` 返回 `0`

## 项目结构

```txt
src/
  Vault.sol        手写 ERC4626-style 金库
  YieldVault.sol   基于 OpenZeppelin ERC4626 的标准金库

script/
  DeFi.s.sol       部署脚本，待实现

test/
  DeFi.t.sol       Foundry 测试，待实现
```

## 安装依赖

本项目使用 Foundry 和 OpenZeppelin Contracts。

如果依赖已经存在，可以直接编译；如果需要重新安装：

```shell
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std
```

## 编译

```shell
forge build
```

## 测试

待补充。

## 部署

待补充。
