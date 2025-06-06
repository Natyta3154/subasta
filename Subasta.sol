// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract Auction {
    address public immutable owner;
    address public winner; //variable ganador 
    uint public winningBid; // variable de oferta ganadora
    uint public auctionStartTime; // hora de inicio de la subasta
    uint public auctionEndTime; //variable de tiempo de finalización de la subasta
    bool public finalized; // variable booleana finalizada 
    bool public commissionWithdrawn;


uint public constant EXTENSION_TIME = 10 minutes;
uint public constant MIN_GLOBAL_INCREMENT_PERCENTAGE = 5; // represents 105%. i.e., +5%
uint public constant COMMISSION_PERCENTAGE = 2; // 2% commission
uint public constant MIN_OWN_BID_INCREMENT_PERCENTAGE = 1; // To exceed previous own bid (2%)

struct ParticipantBid{
    uint currentAmount;
    uint totalDeposited;
    bool exists;
}

mapping(address => ParticipantBid) public bids;
address[] public bidderList;


//eventos 
event NewBid(address indexed bidder, uint amount);
event AuctionFinalized(address indexed winner, uint winningAmount);
event ExcessWithdrawn(address indexed participant, uint amount);
event LoserRefunded(address indexed loser, uint refundedAmount);

//funcion soloMientrasActiva 
modifier onlyWhileActive(){
    require(block.timestamp < auctionEndTime, "Subasta: La subasta ha terminado.");
    require(!finalized, "Subasta: La subasta ya se ha finalizado manualmente.");
    _;
}
// solo el dueno puede realizar esta accion 
modifier onlyOwner(){
    require( msg.sender == owner, "Subasta: Solo el propietario puede ejecutar esto.");
    _;
}

constructor (uint _durationSeconds){
    owner = msg.sender;
    auctionStartTime = block.timestamp;
    auctionEndTime = auctionStartTime + _durationSeconds;

}

// funcion para las ofertas
function bid() external payable onlyWhileActive{
    require(msg.value > 0, "Debes enviar ETH.");

    ParticipantBid storage userBid = bids[msg.sender];
    uint newTotalBid = msg.value;


// La nueva oferta debe ser 2% mayor que la oferta propia anterior del ofertante 
if (userBid.exists && userBid.currentAmount > 0){
    uint minOwnAmount = userBid.currentAmount + (userBid.currentAmount * MIN_OWN_BID_INCREMENT_PERCENTAGE)/100;
    require(newTotalBid >= minOwnAmount, "Subasta: Su oferta debe exceder su oferta actual en al menos un 5%.");

}
// La nueva oferta debe ser 5% mayor que la oferta ganadora global actual 
if (winningBid == 0){
    require(newTotalBid >= 0, "Subasta: La primera oferta debe ser mayor que cero." );
} else {
    uint minGlobalAmount = winningBid + (winningBid * MIN_GLOBAL_INCREMENT_PERCENTAGE)/100;
    require(newTotalBid >= minGlobalAmount, "Subasta: Su oferta debe exceder la oferta actual en al menos un 5%.");
}

//Actualizar el estado dl usuario
if (!userBid.exists){
    bidderList.push(msg.sender);
    userBid.exists = true;
}
userBid.totalDeposited += msg.value;
userBid.currentAmount = newTotalBid;


// Si esta nueva oferta es la más alta, actualiza el ganador global
if (newTotalBid > winningBid){
winningBid = newTotalBid;
winner = msg.sender;
}


//extender si quedan  menos de 10 minutos 
if (auctionEndTime - block.timestamp <= EXTENSION_TIME){
    auctionEndTime += EXTENSION_TIME;
}
emit NewBid(msg.sender, newTotalBid);
}

// tiempo restante de la subasta 
function timeLeft() external view returns (uint) {
        if (block.timestamp >= auctionEndTime) {
            return 0; // La subasta ha terminado
        } else {
            return auctionEndTime - block.timestamp; // Segundos restantes
        }
        }

//La función withdrawExcess  es la encargada de manejar los retiros de fondos.
//retirar excededente
function withdrawExcess() external {
    ParticipantBid storage userBid = bids[msg.sender];
    require(userBid.totalDeposited > 0, "Subasta: Usted no ha hecho ninguna oferta o no tiene depositos." );

    uint amountToWithdraw = 0;

    
    // Si la subasta ha finalizado y el usuario no es el ganador, puede retirar todo su depósito (menos comisión).
    if (finalized && msg.sender != winner){
        amountToWithdraw = userBid.totalDeposited - (userBid.totalDeposited * COMMISSION_PERCENTAGE)/100;
        userBid.totalDeposited = 0;
        // IMPORTANTE: Asegurarse de que el montoActual también se "limpie" para el perdedor si se ha reembolsado todo.
        // Esto es crucial para que `mostrarOfertas` refleje 0 para los que retiraron.

        userBid.currentAmount = 0;
        emit LoserRefunded(msg.sender, amountToWithdraw);
    }else {
         // Si la subasta aún no ha terminado o el usuario es el ganador temporal/final,
            // solo puede retirar el excedente si su depósito es mayor que su oferta actual.
         require(userBid.totalDeposited > userBid.currentAmount, "Subasta: No hay exceso para retirarse en este momento.");
            amountToWithdraw = userBid.totalDeposited - userBid.currentAmount;
            userBid.totalDeposited -= amountToWithdraw;
            emit ExcessWithdrawn(msg.sender, amountToWithdraw);
    }
     (bool success,) = payable (msg.sender).call{value: amountToWithdraw}("");
    require(success, "Subasta: No se transfirio la cantidad.");
}
//finalizar subasta
function finalizeAuction() external onlyOwner{
    require(block.timestamp >= auctionEndTime, "Subasta: La subasta no ha terminado.");
    require(!finalized, "La subasta ya ha finalizado.");

    finalized = true;
    emit AuctionFinalized(winner, winningBid);
}

//mostrar ganador de la oferta retorna   la direccion y el monto con el cual gano 
function showWinner() external view returns (address, uint){
    require(finalized, "La subasta aun no se ha finalizado.");
    return (winner, winningBid);
}

//mostrar ofertas
function showBids() external view returns (address[] memory, uint[] memory){
    uint[] memory amounts = new uint[](bidderList.length);
    for (uint i = 0; i < bidderList.length; i++){
        amounts[i] = bids[bidderList[i]].currentAmount;
    }
    return (bidderList, amounts);
}
// retirra comision
function withdrawCommission() external onlyOwner {
        require(finalized, "Subasta: La subasta debe ser finalizada para retirar la comision.");
        require(winningBid > 0, "Subasta: No hay oferta ganadora para calcular la comision.");
        require(!commissionWithdrawn, "Subasta: La comision ya ha sido retirada.");

        uint commission = (winningBid * COMMISSION_PERCENTAGE) / 100;

        require(commission > 0, "Subasta: No hay comision para retirar o ya ha sido retirado.");

        commissionWithdrawn = true;

       (bool success, ) = payable(owner).call{value: commission}("");
        require(success, "Subasta: No retiro la comision.");
    }

}
