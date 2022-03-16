// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract Zapper is Ownable {
    using SafeERC20 for IERC20;

    event ZappedInLP(
        address indexed who,
        address indexed pairAddress,
        uint256 indexed lpAmount
    );

    function zapInWithPath(
        address _tokenInAddress,
        address _pairAddress,
        uint256 _tokenInAmount,
        address _routerAddress,
        address[] calldata _swapPath
    ) public {
        require(_tokenInAddress != address(0), "!TokenIn address");
        require(_pairAddress != address(0), "!LP address");
        require(_routerAddress != address(0), "!Router address");
        require(_tokenInAmount > 0, "!tokenInAmount");
        require(_swapPath.length >= 2, "!path");

        IUniswapV2Pair pair = _validatePairForRouter(
            _pairAddress,
            _tokenInAddress,
            _routerAddress
        );

        _pullCallersTokens(_tokenInAddress, _tokenInAmount);

        (address tokenIn, address tokenOut) = _getTokenInTokenOut(
            _tokenInAddress,
            pair
        );

        uint256 liquidity = _swapAndAddLiquidity(
            _pairAddress,
            _tokenInAmount,
            _routerAddress,
            _swapPath,
            tokenIn,
            tokenOut
        );

        _returnAssets(_swapPath);

        emit ZappedInLP(msg.sender, _pairAddress, liquidity);
    }

    /// @dev Set routing path accordingly for the pair, given the desired input token
    function _getTokenInTokenOut(address _tokenInAddress, IUniswapV2Pair pair)
        internal
        view
        returns (address tokenIn, address tokenOut)
    {
        bool isInputA = pair.token0() == _tokenInAddress;
        if (isInputA) {
            tokenIn = pair.token0();
            tokenOut = pair.token1();
        } else {
            tokenIn = pair.token1();
            tokenOut = pair.token0();
        }
    }

    function _pullCallersTokens(address _tokenInAddress, uint256 _tokenInAmount)
        internal
    {
        require(_tokenInAmount > 0, "Zero amount");
        require(
            ERC20(_tokenInAddress).allowance(msg.sender, address(this)) >=
                _tokenInAmount,
            "Input token is not approved"
        );
        require(
            ERC20(_tokenInAddress).balanceOf(msg.sender) >= _tokenInAmount,
            "User balance too low"
        );

        // Pull in callers tokens and setup for swap before LP
        IERC20(_tokenInAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenInAmount
        );
    }

    function _swapAndAddLiquidity(
        address _pairAddress,
        uint256 _tokenInAmount,
        address _routerAddress,
        address[] calldata _swapPath,
        address tokenIn,
        address otherToken
    ) internal returns (uint256 liquidity) {
        uint256[] memory amounts = _swap(
            _tokenInAmount,
            tokenIn,
            _routerAddress,
            _swapPath
        );

        uint256 tokenInLpAmount = amounts[0];
        uint256 otherTokenLpAmount = amounts[amounts.length - 1];
        liquidity = _addLiquidity(
            tokenIn,
            otherToken,
            _pairAddress,
            _routerAddress,
            tokenInLpAmount,
            otherTokenLpAmount
        );
    }

    /// @dev sells half of `_tokenInAmount` for the output token of `path`.
    function _swap(
        uint256 _tokenInAmount,
        address _tokenIn,
        address _routerAddress,
        address[] memory _swapPath
    ) internal returns (uint256[] memory) {
        _approveRouter(_tokenIn, _routerAddress);

        uint256 halfAmountIn = _tokenInAmount / 2;

        return
            IUniswapV2Router(_routerAddress).swapExactTokensForTokens(
                halfAmountIn,
                0,
                _swapPath,
                address(this),
                block.timestamp
            );
    }

    function _addLiquidity(
        address _tokenIn,
        address _otherToken,
        address _pairAddress,
        address _routerAddress,
        uint256 _tokenInLpAmount,
        uint256 _otherTokenLpAmount
    ) internal returns (uint256 liquidity) {
        _approveRouter(_otherToken, _routerAddress);
        _approveRouter(_pairAddress, _routerAddress);
        (, , liquidity) = IUniswapV2Router(_routerAddress).addLiquidity(
            _tokenIn,
            _otherToken,
            _tokenInLpAmount,
            _otherTokenLpAmount,
            0,
            0,
            msg.sender,
            block.timestamp
        );
    }

    function _validatePairForRouter(
        address _pairAddress,
        address _inputTokenAddress,
        address _routerAddress
    ) internal view returns (IUniswapV2Pair pair) {
        // Validate input token and LP pair against router
        pair = IUniswapV2Pair(_pairAddress);
        require(
            pair.factory() == IUniswapV2Router(_routerAddress).factory(),
            "Incompatible liquidity pair factory"
        );
        require(
            pair.token0() == _inputTokenAddress ||
                pair.token1() == _inputTokenAddress,
            "Input token not present in liquidity pair"
        );
    }

    function _approveRouter(address _tokenAddress, address _routerAddress)
        internal
    {
        if (
            IERC20(_tokenAddress).allowance(address(this), _routerAddress) == 0
        ) {
            IERC20(_tokenAddress).safeApprove(
                _routerAddress,
                type(uint256).max
            );
        }
    }

    /// @dev Return any dust left over to caller after operations are complete
    function _returnAssets(address[] memory _tokens) internal {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);
            uint256 crumbs = token.balanceOf(address(this));
            if (crumbs > 0) {
                token.safeTransfer(msg.sender, crumbs);
            }
        }
    }

    /// @dev return any stuck tokens if needed for some reason
    function adminReturnAssets(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyOwner {
        require(_token != address(0), "Token address");
        require(_amount > 0, "Zero amount");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance >= _amount, "Zero amount");
        IERC20(_token).safeTransfer(_receiver, _amount);
    }
}
