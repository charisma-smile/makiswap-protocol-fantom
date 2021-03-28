// SPDX-License-Ideuntifier: MIT

pragma solidity ^0.6.12;

// ** LOCAL IMPORTS ** //
import 'makiswap-core/contracts/interfaces/IMakiswapFactory.sol';
import 'maki-swap-lib/contracts/utils/TransferHelper.sol';
// import 'maki-swap-periphery/contracts/libraries/MakiswapLibrary.sol';
// import 'maki-swap-periphery/contracts/interfaces/IMakiswapRouter02.sol';
// import 'maki-swap-lib/contracts/math/SafeMath.sol';

// ** GLOBAL IMPORTS ** //
import './interfaces/IMakiswapRouter02.sol';
import './libraries/MakiswapLibrary.sol';
import './interfaces/IHRC20.sol';
import './interfaces/IWHT.sol';

contract MakiswapRouter is IMakiswapRouter02 {
    using SafeMath for uint;

    address public override factory;

    address public override WHT;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'MakiswapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WHT) public {
        factory = _factory;
        WHT = _WHT;
    }

    receive() external payable {
        assert(msg.sender == WHT); // only accept HT via fallback from the WHT contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IMakiswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IMakiswapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = MakiswapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = MakiswapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'MakiswapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = MakiswapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'MakiswapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = MakiswapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IMakiswapPair(pair).mint(to);
    }
    function addLiquidityHT(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountHTMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountHT, uint liquidity) {
        (amountToken, amountHT) = _addLiquidity(
            token,
            WHT,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountHTMin
        );
        address pair = MakiswapLibrary.pairFor(factory, token, WHT);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWHT(WHT).deposit{value: amountHT}();
        assert(IWHT(WHT).transfer(pair, amountHT));
        liquidity = IMakiswapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountHT) TransferHelper.safeTransferHT(msg.sender, msg.value - amountHT);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = MakiswapLibrary.pairFor(factory, tokenA, tokenB);
        IMakiswapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IMakiswapPair(pair).burn(to);
        (address token0,) = MakiswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'MakiswapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'MakiswapRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityHT(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountHTMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountHT) {
        (amountToken, amountHT) = removeLiquidity(
            token,
            WHT,
            liquidity,
            amountTokenMin,
            amountHTMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWHT(WHT).withdraw(amountHT);
        TransferHelper.safeTransferHT(to, amountHT);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = MakiswapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IMakiswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityHTWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountHTMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountHT) {
        address pair = MakiswapLibrary.pairFor(factory, token, WHT);
        uint value = approveMax ? uint(-1) : liquidity;
        IMakiswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountHT) = removeLiquidityHT(token, liquidity, amountTokenMin, amountHTMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityHTSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountHTMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountHT) {
        (, amountHT) = removeLiquidity(
            token,
            WHT,
            liquidity,
            amountTokenMin,
            amountHTMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IHRC20(token).balanceOf(address(this)));
        IWHT(WHT).withdraw(amountHT);
        TransferHelper.safeTransferHT(to, amountHT);
    }
    function removeLiquidityHTWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountHTMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountHT) {
        address pair = MakiswapLibrary.pairFor(factory, token, WHT);
        uint value = approveMax ? uint(-1) : liquidity;
        IMakiswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountHT = removeLiquidityHTSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountHTMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = MakiswapLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? MakiswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IMakiswapPair(MakiswapLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = MakiswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'MakiswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, MakiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = MakiswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'MakiswapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, MakiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactHTForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WHT, 'MakiswapRouter: INVALID_PATH');
        amounts = MakiswapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'MakiswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWHT(WHT).deposit{value: amounts[0]}();
        assert(IWHT(WHT).transfer(MakiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactHT(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WHT, 'MakiswapRouter: INVALID_PATH');
        amounts = MakiswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'MakiswapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, MakiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWHT(WHT).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferHT(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForHT(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WHT, 'MakiswapRouter: INVALID_PATH');
        amounts = MakiswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'MakiswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, MakiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWHT(WHT).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferHT(to, amounts[amounts.length - 1]);
    }
    function swapHTForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WHT, 'MakiswapRouter: INVALID_PATH');
        amounts = MakiswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'MakiswapRouter: EXCESSIVE_INPUT_AMOUNT');
        IWHT(WHT).deposit{value: amounts[0]}();
        assert(IWHT(WHT).transfer(MakiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferHT(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = MakiswapLibrary.sortTokens(input, output);
            IMakiswapPair pair = IMakiswapPair(MakiswapLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IHRC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = MakiswapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? MakiswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, MakiswapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IHRC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IHRC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'MakiswapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactHTForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WHT, 'MakiswapRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWHT(WHT).deposit{value: amountIn}();
        assert(IWHT(WHT).transfer(MakiswapLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IHRC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IHRC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'MakiswapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForHTSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WHT, 'MakiswapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, MakiswapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IHRC20(WHT).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'MakiswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWHT(WHT).withdraw(amountOut);
        TransferHelper.safeTransferHT(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return MakiswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return MakiswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return MakiswapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return MakiswapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return MakiswapLibrary.getAmountsIn(factory, amountOut, path);
    }
}