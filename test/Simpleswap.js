const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SimpleSwap", function () {
  let SimpleSwap, Token, simpleSwap, tokenA, tokenB, owner, user;
  const ONE_TOKEN = ethers.parseUnits("1", 18);
  const TEN_TOKENS = ethers.parseUnits("10", 18);

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    const TokenFactory = await ethers.getContractFactory("Token");
    tokenA = await TokenFactory.deploy("Token A", "TKNA");
    tokenB = await TokenFactory.deploy("Token B", "TKNB");
    await tokenA.waitForDeployment();
    await tokenB.waitForDeployment();

    const SimpleSwapFactory = await ethers.getContractFactory("SimpleSwap");
    simpleSwap = await SimpleSwapFactory.deploy();
    await simpleSwap.waitForDeployment();

    if (!tokenA.target || !tokenB.target || !simpleSwap.target) {
      throw new Error("Contrato no desplegado correctamente");
    }

    await tokenA.mint(user.address, TEN_TOKENS);
    await tokenB.mint(user.address, TEN_TOKENS);

    await tokenA.connect(user).approve(simpleSwap.target, TEN_TOKENS);
    await tokenB.connect(user).approve(simpleSwap.target, TEN_TOKENS);
  });

  describe("addLiquidity", function () {
    it("debería agregar liquidez inicial correctamente", async function () {
      const amountA = ONE_TOKEN;
      const amountB = ethers.parseUnits("0.01", 18);
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      await expect(
        simpleSwap
          .connect(user)
          .addLiquidity(
            tokenA.target,
            tokenB.target,
            amountA,
            amountB,
            0,
            0,
            user.address,
            deadline
          )
      )
        .to.emit(simpleSwap, "LiquidityAdded")
        .withArgs(
          tokenA.target,
          tokenB.target,
          amountA,
          amountB,
          ethers.parseUnits("0.1", 18),
          user.address
        );

      const reserves = await simpleSwap.reserves(tokenA.target, tokenB.target);
      expect(reserves.reserveA).to.equal(amountA);
      expect(reserves.reserveB).to.equal(amountB);
    });

    it("debería revertir si el deadline ha expirado", async function () {
      const amountA = ONE_TOKEN;
      const amountB = ethers.parseUnits("0.01", 18);
      const block = await ethers.provider.getBlock("latest");
      const pastDeadline = block.timestamp - 3600;

      await expect(
        simpleSwap
          .connect(user)
          .addLiquidity(
            tokenA.target,
            tokenB.target,
            amountA,
            amountB,
            0,
            0,
            user.address,
            pastDeadline
          )
      ).to.be.revertedWith("EXPIRED");
    });
  });

  describe("removeLiquidity", function () {
    it("debería remover liquidez correctamente", async function () {
      const amountA = ONE_TOKEN; // 1e18
      const amountB = ethers.parseUnits("0.01", 18); // 0.01e18
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      await simpleSwap
        .connect(user)
        .addLiquidity(
          tokenA.target,
          tokenB.target,
          amountA,
          amountB,
          0,
          0,
          user.address,
          deadline
        );

      const liquidityToken = await ethers.getContractAt(
        "LiquidityToken",
        await simpleSwap.liquidityToken()
      );
      const liquidity = await liquidityToken.balanceOf(user.address);

      await liquidityToken.connect(user).approve(simpleSwap.target, liquidity);

      // Determinar el orden de los tokens
      const isSorted = tokenA.target < tokenB.target;
      const expectedAmount0 = isSorted ? amountA : amountB;
      const expectedAmount1 = isSorted ? amountB : amountA;

      await expect(
        simpleSwap
          .connect(user)
          .removeLiquidity(
            tokenA.target,
            tokenB.target,
            liquidity,
            0,
            0,
            user.address,
            deadline
          )
      )
        .to.emit(simpleSwap, "LiquidityRemoved")
        .withArgs(
          tokenA.target,
          tokenB.target,
          expectedAmount0,
          expectedAmount1,
          liquidity,
          user.address
        );

      const reserves = await simpleSwap.reserves(
        isSorted ? tokenA.target : tokenB.target,
        isSorted ? tokenB.target : tokenA.target
      );
      expect(reserves.reserveA).to.equal(0);
      expect(reserves.reserveB).to.equal(0);
    });

    it("debería revertir si la cantidad mínima no se cumple", async function () {
      const amountA = ONE_TOKEN;
      const amountB = ethers.parseUnits("0.01", 18);
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      await simpleSwap
        .connect(user)
        .addLiquidity(
          tokenA.target,
          tokenB.target,
          amountA,
          amountB,
          0,
          0,
          user.address,
          deadline
        );

      const liquidityToken = await ethers.getContractAt(
        "LiquidityToken",
        await simpleSwap.liquidityToken()
      );
      const liquidity = await liquidityToken.balanceOf(user.address);

      await liquidityToken.connect(user).approve(simpleSwap.target, liquidity);

      await expect(
        simpleSwap
          .connect(user)
          .removeLiquidity(
            tokenA.target,
            tokenB.target,
            liquidity,
            ethers.parseUnits("100", 18),
            ethers.parseUnits("100", 18),
            user.address,
            deadline
          )
      ).to.be.revertedWith("INSUFFICIENT_A_AMOUNT");
    });
  });

  describe("swapExactTokensForTokens", function () {
    it("debería realizar un swap de Token A a Token B correctamente", async function () {
      const amountA = ONE_TOKEN;
      const amountB = ethers.parseUnits("0.01", 18);
      const amountIn = ethers.parseUnits("0.1", 18);
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      await simpleSwap
        .connect(user)
        .addLiquidity(
          tokenA.target,
          tokenB.target,
          amountA,
          amountB,
          0,
          0,
          user.address,
          deadline
        );

      const amountOut = await simpleSwap.getAmountOut(
        amountIn,
        amountA,
        amountB
      );
      await expect(
        simpleSwap
          .connect(user)
          .swapExactTokensForTokens(
            amountIn,
            0,
            [tokenA.target, tokenB.target],
            user.address,
            deadline
          )
      )
        .to.emit(simpleSwap, "Swapped")
        .withArgs(
          tokenA.target,
          tokenB.target,
          amountIn,
          amountOut,
          user.address
        );

      const reserves = await simpleSwap.reserves(tokenA.target, tokenB.target);
      expect(reserves.reserveA).to.equal(amountA + amountIn);
      expect(reserves.reserveB).to.equal(amountB - amountOut);
    });

    it("debería revertir si no hay liquidez", async function () {
      const amountIn = ethers.parseUnits("0.1", 18);
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      await expect(
        simpleSwap
          .connect(user)
          .swapExactTokensForTokens(
            amountIn,
            0,
            [tokenA.target, tokenB.target],
            user.address,
            deadline
          )
      ).to.be.revertedWith("INSUFFICIENT_LIQUIDITY");
    });
  });

  describe("getPrice", function () {
    it("debería devolver el precio de Token A en Token B", async function () {
      const amountA = ONE_TOKEN;
      const amountB = ethers.parseUnits("0.01", 18);
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      await simpleSwap
        .connect(user)
        .addLiquidity(
          tokenA.target,
          tokenB.target,
          amountA,
          amountB,
          0,
          0,
          user.address,
          deadline
        );

      const price = await simpleSwap.getPrice(tokenA.target, tokenB.target);
      const expectedPrice = (amountB * ethers.parseUnits("1", 18)) / amountA;
      expect(price).to.equal(expectedPrice);
    });

    it("debería devolver el precio de Token B en Token A", async function () {
      const amountA = ONE_TOKEN;
      const amountB = ethers.parseUnits("0.01", 18);
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      await simpleSwap
        .connect(user)
        .addLiquidity(
          tokenA.target,
          tokenB.target,
          amountA,
          amountB,
          0,
          0,
          user.address,
          deadline
        );

      const price = await simpleSwap.getPrice(tokenB.target, tokenA.target);
      const expectedPrice = (amountA * ethers.parseUnits("1", 18)) / amountB;
      expect(price).to.equal(expectedPrice);
    });

    it("debería revertir si no hay liquidez", async function () {
      await expect(
        simpleSwap.getPrice(tokenA.target, tokenB.target)
      ).to.be.revertedWith("INSUFFICIENT_LIQUIDITY");
    });
  });
});
