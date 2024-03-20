import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { FP_ZERO, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/WETHTestToken';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { StablePoolFactory } from '../typechain-types';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { MAX_UINT256 } from '@balancer-labs/v3-helpers/src/constants';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { PoolConfigStructOutput } from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';

describe('StablePool', () => {
  const TOKEN_AMOUNT = fp(1000);

  let vault: IVaultMock;
  let router: Router;
  let alice: SignerWithAddress;
  let tokens: ERC20TokenList;
  let factory: StablePoolFactory;
  let pool: Contract;
  let poolTokens: string[];

  before('setup signers', async () => {
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, factory, and tokens', async function () {
    vault = await TypesConverter.toIVaultMock(await VaultDeployer.deployMock());

    const WETH: WETHTestToken = await deploy('v3-solidity-utils/WETHTestToken');
    router = await deploy('v3-vault/Router', { args: [vault, await WETH.getAddress()] });

    factory = await deploy('StablePoolFactory', { args: [await vault.getAddress(), MONTH * 12] });

    tokens = await ERC20TokenList.create(4, { sorted: true });
    poolTokens = await tokens.addresses;

    // mint and approve tokens
    await tokens.asyncEach(async (token) => {
      await token.mint(alice, TOKEN_AMOUNT);
      await token.connect(alice).approve(vault, MAX_UINT256);
    });
  });

  for (let i = 2; i <= 4; i++) {
    itDeploysAStablePool(i);
  }

  async function deployPool(numTokens: number) {
    const tx = await factory.create(
      'Stable Pool',
      `STABLE-${numTokens}`,
      buildTokenConfig(poolTokens.slice(0, numTokens)),
      200n,
      TypesConverter.toBytes32(bn(numTokens))
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const poolAddress = event.args.pool;

    pool = await deployedAt('StablePool', poolAddress);
  }

  function itDeploysAStablePool(numTokens: number) {
    it(`${numTokens} token pool was deployed correctly`, async () => {
      await deployPool(numTokens);

      expect(await pool.name()).to.equal('Stable Pool');
      expect(await pool.symbol()).to.equal(`STABLE-${numTokens}`);
    });

    describe(`initialization with ${numTokens} tokens`, () => {
      let initialBalances: bigint[];

      context('uninitialized', () => {
        it('is registered, but not initialized on deployment', async () => {
          await deployPool(numTokens);

          const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

          expect(poolConfig.isPoolRegistered).to.be.true;
          expect(poolConfig.isPoolInitialized).to.be.false;
        });
      });

      context('initialized', () => {
        sharedBeforeEach('initialize pool', async () => {
          await deployPool(numTokens);
          initialBalances = Array(numTokens).fill(TOKEN_AMOUNT);

          expect(
            await router
              .connect(alice)
              .initialize(pool, poolTokens.slice(0, numTokens), initialBalances, FP_ZERO, false, '0x')
          )
            .to.emit(vault, 'PoolInitialized')
            .withArgs(pool);
        });

        it('is registered and initialized', async () => {
          const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

          expect(poolConfig.isPoolRegistered).to.be.true;
          expect(poolConfig.isPoolInitialized).to.be.true;
          expect(poolConfig.isPoolPaused).to.be.false;
        });

        it('has the correct pool tokens and balances', async () => {
          const tokensFromPool = await pool.getPoolTokens();
          expect(tokensFromPool).to.deep.equal(poolTokens.slice(0, numTokens));

          const [tokensFromVault, , balancesFromVault] = await vault.getPoolTokenInfo(pool);
          expect(tokensFromVault).to.deep.equal(tokensFromPool);
          expect(balancesFromVault).to.deep.equal(initialBalances);
        });

        it('cannot be initialized twice', async () => {
          await expect(router.connect(alice).initialize(pool, poolTokens, initialBalances, FP_ZERO, false, '0x'))
            .to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized')
            .withArgs(await pool.getAddress());
        });
      });
    });
  }
});