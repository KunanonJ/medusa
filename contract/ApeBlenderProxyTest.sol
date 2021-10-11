//SPDX-License-Identifier: Unlicense
pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IWETH.sol";
import "./uniswap/Math.sol";

contract ApeBlenderProxyTest is Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public apeFeeBps;
    address payable public feeTreasury;
    IWETH public wNative;
    IUniswapV2Router02 public exchangeRouter;
    uint256 public exchangeSwapFeeNumerator; // 3 for Uniswap, 25 for Pancakeswap
    uint256 public exchangeSwapFeeDenominator; // 1000 for Uniswap, 10000 for Pancakeswap

    uint256 MAX;

    function initialize(
        uint256 _apeFeeBps,
        address payable _feeTreasury,
        address _exchangeRouter,
        address _wNative,
        uint256 _exchangeSwapFeeNumerator,
        uint256 _exchangeSwapFeeDenominator
    ) public payable initializer {
        apeFeeBps = _apeFeeBps;
        feeTreasury = _feeTreasury;
        exchangeRouter = IUniswapV2Router02(_exchangeRouter);
        wNative = IWETH(_wNative);
        exchangeSwapFeeNumerator = _exchangeSwapFeeNumerator;
        exchangeSwapFeeDenominator = _exchangeSwapFeeDenominator;
        MAX = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    }

    function setApeFeeBps(uint256 _apeFeeBps) public {
        apeFeeBps = _apeFeeBps;
    }

    receive() external payable {}

    struct InputToken {
        address token;
        uint256 amount;
        address[] tokenToNativePath;
    }

    struct InputLP {
        address token;
        uint256 amount;
        address[] token0ToNativePath;
        address[] token1ToNativePath;
    }

    function transferNativeFeeToTreasury(uint256 amount)
        private
        returns (uint256)
    {
        if (apeFeeBps == 0) {
            return amount;
        }
        uint256 fee = apeFeeBps.mul(amount).div(10000);
        //https://ethereum.stackexchange.com/questions/19341/address-send-vs-address-transfer-best-practice-usage/74007#74007
        (bool success, ) = feeTreasury.call{value: fee}("");
        require(success, "Transfer failed.");
        return amount.sub(fee);
    }

    function transferTokenFeeToTreasury(address token, uint256 amount)
        private
        returns (uint256)
    {
        if (apeFeeBps == 0) {
            return amount;
        }
        uint256 fee = apeFeeBps.mul(amount).div(10000);
        IERC20(token).transfer(feeTreasury, fee);
        return amount.sub(fee);
    }

    function swapTokensToToken(
        InputToken[] memory inputTokens,
        InputLP[] memory inputLPs,
        address[] memory nativeToOutputPath,
        uint256 minOutputAmount
    ) public payable {
        if (msg.value > 0) {
            wNative.deposit{value: msg.value}();
        }
        if (inputLPs.length > 0) {
            _transferTokensToApe(inputLPs);
            _swapTokensForNative(_removeLiquidity(inputLPs));
        }
        if (inputTokens.length > 0) {
            _transferTokensToApe(inputTokens);
            _swapTokensForNative(inputTokens);
        }
        uint256 wNativeBalance = IERC20(address(wNative)).balanceOf(
            address(this)
        );
        uint256 amountOut = _swapNativeForToken(
            wNativeBalance,
            nativeToOutputPath
        );
        amountOut = transferTokenFeeToTreasury(
            nativeToOutputPath[nativeToOutputPath.length - 1],
            amountOut
        );
        require(
            amountOut >= minOutputAmount,
            "Expect amountOut to be greater than minOutputAmount."
        );
        IERC20(nativeToOutputPath[nativeToOutputPath.length - 1]).safeTransfer(
            msg.sender,
            amountOut
        );
    }

    function swapTokensToLP(
        InputToken[] memory inputTokens,
        InputLP[] memory inputLPs,
        address outputLP,
        uint256 minOutputAmount
    ) public payable {
        address token0 = IUniswapV2Pair(outputLP).token0();
        address token1 = IUniswapV2Pair(outputLP).token1();
        if (msg.value > 0) {
            wNative.deposit{value: msg.value}();
        }
        if (inputLPs.length > 0) {
            _transferTokensToApe(inputLPs);
            _swapTokensForNativeExcept(
                _removeLiquidity(inputLPs),
                token0,
                token1
            );
        }
        if (inputTokens.length > 0) {
            _transferTokensToApe(inputTokens);
            _swapTokensForNativeExcept(inputTokens, token0, token1);
        }
        uint256 amountOut = _optimalSwapToLp(
            outputLP,
            token0,
            token1,
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this))
        );
        amountOut = transferTokenFeeToTreasury(outputLP, amountOut);
        require(
            amountOut >= minOutputAmount,
            "Expect amountOut to be greater than minOutputAmount."
        );
        IERC20(outputLP).safeTransfer(msg.sender, amountOut);
    }

    // Token version
    function _transferTokensToApe(InputToken[] memory inputTokens)
        private
        returns (uint256[] memory)
    {
        uint256[] memory outputAmounts = new uint256[](inputTokens.length);
        for (uint256 i = 0; i < inputTokens.length; i++) {
            IERC20(inputTokens[i].token).safeTransferFrom(
                msg.sender,
                address(this),
                inputTokens[i].amount
            );
            outputAmounts[i] = inputTokens[i].amount;
        }
        return outputAmounts;
    }

    // LP version
    function _transferTokensToApe(InputLP[] memory inputLPs)
        private
        returns (uint256[] memory)
    {
        uint256[] memory outputAmounts = new uint256[](inputLPs.length);
        for (uint256 i = 0; i < inputLPs.length; i++) {
            IERC20(inputLPs[i].token).safeTransferFrom(
                msg.sender,
                address(this),
                inputLPs[i].amount
            );
            outputAmounts[i] = inputLPs[i].amount;
        }
        return outputAmounts;
    }

    function _removeLiquidity(InputLP[] memory inputLPs)
        private
        returns (InputToken[] memory)
    {
        InputToken[] memory outputTokens = new InputToken[](
            inputLPs.length * 2
        );
        for (uint256 i = 0; i < inputLPs.length; i++) {
            IERC20(inputLPs[i].token).approve(address(exchangeRouter), MAX);
            (uint256 amount0, uint256 amount1) = exchangeRouter.removeLiquidity(
                inputLPs[i].token0ToNativePath[0],
                inputLPs[i].token1ToNativePath[0],
                inputLPs[i].amount,
                0,
                0,
                address(this),
                now + 60
            );
            outputTokens[i * 2] = InputToken(
                inputLPs[i].token0ToNativePath[0],
                amount0,
                inputLPs[i].token0ToNativePath
            );
            outputTokens[(i * 2) + 1] = InputToken(
                inputLPs[i].token1ToNativePath[0],
                amount1,
                inputLPs[i].token1ToNativePath
            );
        }
        return outputTokens;
    }

    function _swapTokensForNative(InputToken[] memory inputTokens)
        private
        returns (uint256)
    {
        uint256 totalNative = 0;
        for (uint256 i = 0; i < inputTokens.length; i++) {
            // Swap non wNative token
            if (inputTokens[i].token != address(wNative)) {
                IERC20(inputTokens[i].token).approve(
                    address(exchangeRouter),
                    MAX
                );
                uint256[] memory amountOuts = exchangeRouter
                .swapExactTokensForTokens(
                    inputTokens[i].amount,
                    0,
                    inputTokens[i].tokenToNativePath,
                    address(this),
                    now + 60
                );
                totalNative = totalNative.add(
                    amountOuts[amountOuts.length - 1]
                );
            }
        }
        return totalNative;
    }

    function _swapTokensForNativeExcept(
        InputToken[] memory inputTokens,
        address token0,
        address token1
    ) private returns (uint256) {
        uint256 totalNative = 0;
        for (uint256 i = 0; i < inputTokens.length; i++) {
            if (
                inputTokens[i].token != token0 && inputTokens[i].token != token1
            ) {
                IERC20(inputTokens[i].token).approve(
                    address(exchangeRouter),
                    MAX
                );
                uint256[] memory amountOuts = exchangeRouter
                .swapExactTokensForTokens(
                    inputTokens[i].amount,
                    0,
                    inputTokens[i].tokenToNativePath,
                    address(this),
                    now + 60
                );
                totalNative = totalNative.add(
                    amountOuts[amountOuts.length - 1]
                );
            }
        }
        return totalNative;
    }

    function _swapNativeForToken(uint256 amount, address[] memory path)
        private
        returns (uint256)
    {
        // if (path.length == 1 && path[0] == address(wNative)) {
        //     wNative.deposit{value: amount}();
        //     return amount;
        // }
        IERC20(address(wNative)).approve(address(exchangeRouter), MAX);
        uint256[] memory amountOuts = exchangeRouter.swapExactTokensForTokens(
            amount,
            0,
            path,
            address(this),
            now + 60
        );
        return amountOuts[amountOuts.length - 1];
    }

    function _optimalSwapToLp(
        address outputLP,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) private returns (uint256) {
        IERC20(token0).approve(address(exchangeRouter), MAX);
        IERC20(token1).approve(address(exchangeRouter), MAX);
        (
            uint256 token0Amount,
            uint256 token1Amount
        ) = _optimalSwapForAddingLiquidity(
            outputLP,
            token0,
            token1,
            amount0,
            amount1
        );
        (
            uint256 addedToken0,
            uint256 addedToken1,
            uint256 lpAmount
        ) = exchangeRouter.addLiquidity(
            token0,
            token1,
            token0Amount,
            token1Amount,
            0,
            0,
            address(this),
            now + 60
        );

        // Transfer dust
        if (token0Amount.sub(addedToken0) > 0) {
            IERC20(token0).safeTransfer(
                msg.sender,
                token0Amount.sub(addedToken0)
            );
        }

        if (token1Amount.sub(addedToken1) > 0) {
            IERC20(token1).safeTransfer(
                msg.sender,
                token1Amount.sub(addedToken1)
            );
        }

        return lpAmount;
    }

    function _optimalSwapForAddingLiquidity(
        address lp,
        address token0,
        address token1,
        uint256 token0Amount,
        uint256 token1Amount
    ) private returns (uint256, uint256) {
        (uint256 res0, uint256 res1, ) = IUniswapV2Pair(lp).getReserves();
        if (res0.mul(token1Amount) == res1.mul(token0Amount)) {
            return (token0Amount, token1Amount);
        }

        bool reverse = token0Amount.mul(res1) < token1Amount.mul(res0);

        uint256 optimalSwapAmount = reverse
            ? calculateOptimalSwapAmount(token1Amount, token0Amount, res1, res0)
            : calculateOptimalSwapAmount(
                token0Amount,
                token1Amount,
                res0,
                res1
            );

        address[] memory path = new address[](2);
        (path[0], path[1]) = reverse ? (token1, token0) : (token0, token1);
        if (optimalSwapAmount > 0) {
            uint256[] memory amountOuts = exchangeRouter
            .swapExactTokensForTokens(
                optimalSwapAmount,
                0,
                path,
                address(this),
                now + 60
            );
            if (reverse) {
                token0Amount = token0Amount.add(
                    amountOuts[amountOuts.length - 1]
                );
                token1Amount = token1Amount.sub(optimalSwapAmount);
            } else {
                token0Amount = token0Amount.sub(optimalSwapAmount);
                token1Amount = token1Amount.add(
                    amountOuts[amountOuts.length - 1]
                );
            }
        }

        return (token0Amount, token1Amount);
    }

    function calculateOptimalSwapAmount(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) public view returns (uint256) {
        require(
            amtA.mul(resB) >= amtB.mul(resA),
            "Expect amtA value to be greater than amtB value"
        );

        uint256 a = exchangeSwapFeeDenominator.sub(exchangeSwapFeeNumerator);
        uint256 b = exchangeSwapFeeDenominator
        .mul(2)
        .sub(exchangeSwapFeeNumerator)
        .mul(resA);

        uint256 c = a.mul(amtA).mul(resA).mul(exchangeSwapFeeDenominator).mul(
            4
        );
        uint256 d = Math.sqrt(b.mul(b).add(c));

        uint256 numerator = d.sub(b);
        uint256 denominator = a.mul(2);

        return numerator.div(denominator);
    }
}