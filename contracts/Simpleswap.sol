// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiquidityToken is ERC20 {
    constructor() ERC20("SimpleSwap Liquidity Token", "SSLT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract SimpleSwap {
    struct Reserve {
        uint256 reserveA;
        uint256 reserveB;
    }

    struct Pair {
        address token0;
        address token1;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct SwapParams {
        address token0;
        address token1;
        uint256 reserveIn;
        uint256 reserveOut;
        bool isSorted;
    }

    mapping(address => mapping(address => Reserve)) public reserves;
    LiquidityToken public liquidityToken;

    event LiquidityAdded(address indexed tokenA, address indexed tokenB, uint amountA, uint amountB, uint liquidity, address indexed to);
    event LiquidityRemoved(address indexed tokenA, address indexed tokenB, uint amountA, uint amountB, uint liquidity, address indexed to);
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint amountIn, uint amountOut, address indexed to);

    constructor() {
        liquidityToken = new LiquidityToken();
    }

    function _getSortedPair(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) private pure returns (Pair memory pair) {
        require(tokenA != tokenB, "IDENTICAL_TOKENS");
        bool isSorted = tokenA < tokenB;
        pair.token0 = isSorted ? tokenA : tokenB;
        pair.token1 = isSorted ? tokenB : tokenA;
        pair.amount0Desired = isSorted ? amountADesired : amountBDesired;
        pair.amount1Desired = isSorted ? amountBDesired : amountADesired;
        pair.amount0Min = isSorted ? amountAMin : amountBMin;
        pair.amount1Min = isSorted ? amountBMin : amountAMin;
    }

    function _calculateLiquidity(
        Reserve storage reserve,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) private view returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        if (reserve.reserveA == 0 && reserve.reserveB == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            liquidity = sqrt(amount0 * amount1);
        } else {
            uint256 amount1Optimal = quote(amount0Desired, reserve.reserveA, reserve.reserveB);
            if (amount1Optimal <= amount1Desired) {
                require(amount1Optimal >= amount1Min, "INSUFFICIENT_AMOUNT");
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = quote(amount1Desired, reserve.reserveB, reserve.reserveA);
                require(amount0Optimal >= amount0Min, "INSUFFICIENT_AMOUNT");
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
            liquidity = min(
                amount0 * liquidityToken.totalSupply() / reserve.reserveA,
                amount1 * liquidityToken.totalSupply() / reserve.reserveB
            );
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(block.timestamp <= deadline, "EXPIRED");

        Pair memory pair = _getSortedPair(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        Reserve storage reserve = reserves[pair.token0][pair.token1];

        (amountA, amountB, liquidity) = _calculateLiquidity(
            reserve,
            pair.amount0Desired,
            pair.amount1Desired,
            pair.amount0Min,
            pair.amount1Min
        );

        _safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        _safeTransferFrom(tokenB, msg.sender, address(this), amountB);

        reserve.reserveA = reserve.reserveA + amountA;
        reserve.reserveB = reserve.reserveB + amountB;
        reserves[pair.token1][pair.token0].reserveA = reserve.reserveB;
        reserves[pair.token1][pair.token0].reserveB = reserve.reserveA;

        liquidityToken.mint(to, liquidity);
        emit LiquidityAdded(tokenA, tokenB, amountA, amountB, liquidity, to);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        require(block.timestamp <= deadline, "EXPIRED");

        Pair memory pair = _getSortedPair(tokenA, tokenB, 0, 0, amountAMin, amountBMin);
        Reserve storage reserve = reserves[pair.token0][pair.token1];
        uint totalSupply = liquidityToken.totalSupply();

        amountA = liquidity * reserve.reserveA / totalSupply;
        amountB = liquidity * reserve.reserveB / totalSupply;

        require(amountA >= pair.amount0Min, "INSUFFICIENT_A_AMOUNT");
        require(amountB >= pair.amount1Min, "INSUFFICIENT_B_AMOUNT");

        liquidityToken.burn(msg.sender, liquidity);
        _safeTransfer(tokenA, to, amountA);
        _safeTransfer(tokenB, to, amountB);

        reserve.reserveA = reserve.reserveA - amountA;
        reserve.reserveB = reserve.reserveB - amountB;

        reserves[pair.token1][pair.token0].reserveA = reserve.reserveB;
        reserves[pair.token1][pair.token0].reserveB = reserve.reserveA;

        emit LiquidityRemoved(tokenA, tokenB, amountA, amountB, liquidity, to);
    }

    function _getSwapParams(
        address tokenIn,
        address tokenOut
    ) private view returns (SwapParams memory params) {
        params.isSorted = tokenIn < tokenOut;
        params.token0 = params.isSorted ? tokenIn : tokenOut;
        params.token1 = params.isSorted ? tokenOut : tokenIn;
        Reserve storage reserve = reserves[params.token0][params.token1];
        params.reserveIn = params.isSorted ? reserve.reserveA : reserve.reserveB;
        params.reserveOut = params.isSorted ? reserve.reserveB : reserve.reserveA;
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(path.length == 2, "INVALID_PATH");

        SwapParams memory params = _getSwapParams(path[0], path[1]);
        require(params.reserveIn > 0 && params.reserveOut > 0, "INSUFFICIENT_LIQUIDITY");

        uint amountOut = getAmountOut(amountIn, params.reserveIn, params.reserveOut);
        require(amountOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        _safeTransferFrom(path[0], msg.sender, address(this), amountIn);
        _safeTransfer(path[1], to, amountOut);

        Reserve storage reserve = reserves[params.token0][params.token1];
        if (params.isSorted) {
            reserve.reserveA = reserve.reserveA + amountIn;
            reserve.reserveB = reserve.reserveB - amountOut;
            reserves[params.token1][params.token0].reserveA = reserve.reserveB;
            reserves[params.token1][params.token0].reserveB = reserve.reserveA;
        } else {
            reserve.reserveB = reserve.reserveB + amountIn;
            reserve.reserveA = reserve.reserveA - amountOut;
            reserves[params.token1][params.token0].reserveA = reserve.reserveB;
            reserves[params.token1][params.token0].reserveB = reserve.reserveA;
        }

        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
        emit Swapped(path[0], path[1], amountIn, amountOut, to);
    }

    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        bool isSorted = tokenA < tokenB;
        address token0 = isSorted ? tokenA : tokenB;
        address token1 = isSorted ? tokenB : tokenA;
        Reserve memory reserve = reserves[token0][token1];
        require(reserve.reserveA > 0 && reserve.reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        price = isSorted ? (reserve.reserveB * 1e18) / reserve.reserveA : (reserve.reserveA * 1e18) / reserve.reserveB;
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        amountB = amountA * reserveB / reserveA;
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function _safeTransferFrom(address token, address from, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}