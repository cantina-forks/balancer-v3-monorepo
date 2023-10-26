import { BigNumberish, Contract, ContractTransaction } from 'ethers';

import { MAX_UINT256 } from '../../constants';

import TokensDeployer from './ERC20TokensDeployer';
import TypesConverter from '../types/TypesConverter';
import { Account, TxParams } from '../types/types';
import { RawTokenDeployment } from './types';
import { deployedAt } from '../../contract';

export default class ERC20Token {
  name: string;
  symbol: string;
  decimals: number;
  instance: Contract;

  static async create(params: RawTokenDeployment): Promise<ERC20Token> {
    return TokensDeployer.deployToken(params);
  }

  static async deployedAt(address: Account): Promise<ERC20Token> {
    const instance = await deployedAt('v3-solidity-utils/ERC20TestToken', TypesConverter.toAddress(address));
    const [name, symbol, decimals] = await Promise.all([instance.name(), instance.symbol(), instance.decimals()]);
    if (symbol === 'WETH') {
      return new ERC20Token(
        name,
        symbol,
        decimals,
        await deployedAt('v3-standalone-utils/TestWETH', TypesConverter.toAddress(address))
      );
    }
    return new ERC20Token(name, symbol, decimals, instance);
  }

  constructor(name: string, symbol: string, decimals: number, instance: Contract) {
    this.name = name;
    this.symbol = symbol;
    this.decimals = decimals;
    this.instance = instance;
  }

  async address(): Promise<string> {
    return this.instance.getAddress();
  }

  async balanceOf(account: Account): Promise<bigint> {
    return this.instance.balanceOf(TypesConverter.toAddress(account));
  }

  async mint(to: Account, amount?: BigNumberish, { from }: TxParams = {}): Promise<void> {
    const token = from ? this.instance.connect(from) : this.instance;

    if (this.symbol === 'WETH') {
      await token.deposit({ value: amount });
      await token.transfer(TypesConverter.toAddress(to), amount);
    } else if (this.symbol !== 'wstETH' && this.symbol != 'wampl') {
      // wstETH and wampl need permissioned calls (wrap() in the case of wstETH); calling it
      // generically from init() would fail. So tests that mint these tokens (e.g.,
      // UnbuttonAaveLinearPool) need to do it separately, and we need to add these exceptions
      // here, so that mint() is a no-op for these tokens.
      await token.mint(TypesConverter.toAddress(to), amount ?? MAX_UINT256);
    }
  }

  async transfer(to: Account, amount: BigNumberish, { from }: TxParams = {}): Promise<ContractTransaction> {
    const token = from ? this.instance.connect(from) : this.instance;
    return token.transfer(TypesConverter.toAddress(to), amount);
  }

  async approve(to: Account, amount?: BigNumberish, { from }: TxParams = {}): Promise<ContractTransaction> {
    const token = from ? this.instance.connect(from) : this.instance;
    return token.approve(TypesConverter.toAddress(to), amount ?? MAX_UINT256);
  }

  async burn(amount: BigNumberish, { from }: TxParams = {}): Promise<ContractTransaction> {
    const token = from ? this.instance.connect(from) : this.instance;
    return token.burn(amount);
  }

  compare(anotherToken: ERC20Token): number {
    return this.address.toLowerCase() > anotherToken.address.toLowerCase() ? 1 : -1;
  }
}