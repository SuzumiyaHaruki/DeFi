# DeFi Vault

这是一个使用 Foundry 编写的 Solidity 练习项目，实现了一个简单的 DeFi 金库合约和一个用于分红的 ERC20 代币。

项目主要包含两个合约：

- `Token.sol`：基于 OpenZeppelin ERC20 的代币合约，部署者拥有增发权限。
- `Vault.sol`：金库合约，支持用户存入 ETH、提取 ETH、在合约内部转移余额，以及按存款比例分配 ERC20 收益。

## 功能说明

### ETH 存款

用户可以调用 `deposit()` 向金库存入 ETH。合约会记录用户的内部余额，并更新全局 `totalDeposits`。

### ETH 提现

用户可以调用 `withdraw(value)` 提取自己的 ETH。合约会先更新用户余额和总存款，再执行 ETH 转账，以减少重入风险。

### 内部转账

用户可以调用 `transfer(to, value)` 将自己在金库中的内部余额转给其他地址。接收地址不能是 `address(0)`。

### 管理员

合约部署者是 owner，同时默认也是 admin。

owner 可以调用：

- `setAdmin(addr)`：添加管理员
- `deleteAdmin(addr)`：移除管理员

admin 可以执行收益分配相关操作。

### 分页收益分配

金库使用 ERC20 代币作为收益分红资产。管理员可以先向金库转入收益代币，然后启动分红：

```solidity
startYieldDistribution()
```

该函数会记录当前 ERC20 收益余额和当前 ETH 总存款快照。

之后管理员可以分批调用：

```solidity
distributeYield(maxUsers)
```

`maxUsers` 表示本次最多处理多少个用户。这样可以避免一次遍历所有用户导致 gas 超限。

分红进行期间，合约会暂时禁止：

- `deposit`
- `withdraw`
- `transfer`

这样可以防止分红快照期间用户余额变化，影响分配公平性。

## 项目结构

```txt
src/
  Token.sol      ERC20 代币合约
  Vault.sol      DeFi 金库合约

script/
  DeFi.s.sol     部署脚本

test/
  DeFi.t.sol     Foundry 测试
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

## 运行测试

```shell
forge test -vv
```

当前测试覆盖：

- 存款
- 提现
- 内部转账
- 零地址校验
- owner/admin 权限
- 分页分红
- 分红期间禁止余额变更

## 部署

本地或测试网部署可以使用：

```shell
forge script script/DeFi.s.sol:DefiScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

部署脚本会：

1. 部署 `Token`
2. 部署 `DeFi`
3. 向 `DeFi` 合约铸造一部分收益代币

## 注意事项

这是一个学习和练习用项目，不建议直接用于生产环境。

当前实现为了便于理解，保留了 `users` 数组并使用分页遍历进行收益分配。在真实 DeFi 协议中，更常见的做法是使用累计收益指数、用户主动领取奖励等机制，以进一步降低 gas 成本并改善可扩展性。
