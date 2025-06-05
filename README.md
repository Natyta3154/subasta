# 📦 Contrato Inteligente de Subasta - Scroll Sepolia

Este contrato implementa una subasta descentralizada en la red Scroll Sepolia. Incluye lógica de extensión de tiempo, ofertas válidas con incremento mínimo, devolución de fondos con comisión, y funcionalidades avanzadas como el retiro parcial de depósitos excedentes.

# 📦 Contrato Inteligente de Subasta - Scroll Sepolia

Este contrato implementa una subasta descentralizada en la red Scroll Sepolia. Incluye lógica de extensión de tiempo, ofertas válidas con incremento mínimo, devolución de fondos con comisión, y funcionalidades avanzadas como el retiro de depósitos excedentes.

---

## 🚀 Descripción General

- Los participantes envían ETH para ofertar por un artículo.
- Cada nueva oferta debe ser **al menos 5% mayor** que la anterior.
- Si alguien oferta durante los **últimos 10 minutos**, se extiende el tiempo de subasta automáticamente por 10 minutos mas.
- Al finalizar, solo el `winner` paga su oferta, los demás reciben sus depósitos menos una **comisión del 2%**.
- Los participantes pueden **retirar su excedente** durante la subasta.

---

## ⚙️ Variables Públicas

| Variable            | Tipo      | Descripción                                                  |
|---------------------|-----------|--------------------------------------------------------------|
| `owner`             | address   | Dirección del creador del contrato.                          |
| `winner`            | address   | Dirección del ofertante con la oferta más alta.              |
| `winningBid`        | uint      | Monto de la oferta ganadora.                                 |
| `auctionStartTime`  | uint      | Timestamp de inicio de la subasta.                           |
| `auctionEndTime`    | uint      | Timestamp de finalización de la subasta.                     |
| `finalized`         | bool      | Indica si la subasta fue finalizada oficialmente.            |
| `bids`              | mapping   | Registro de ofertas por cada dirección ofertante.            |
| `bidderList`        | address[] | Lista de todos los participantes que realizaron ofertas.     |

---

## 📦 Estructura de Datos

### `struct ParticipantBid`

```solidity
struct ParticipantBid {
    uint currentAmount;   // Oferta válida más alta
    uint totalDeposited;  // Total de ETH depositado
    bool exists;          // Indica si el participante ya existe
}
```

---

## 🧠 Funciones

### `constructor(uint _durationSeconds)`
Inicializa la subasta con la duración deseada.

- `@param _durationSeconds`: duración total de la subasta desde el despliegue.

---

### `bid() external payable`
Permite realizar una oferta enviando ETH. La nueva oferta debe ser al menos un 5% mayor que la oferta ganadora actual. Si faltan menos de 10 minutos para terminar, se extiende la subasta.

- Requiere: `msg.value > 0`
- Solo se puede ejecutar mientras la subasta esté activa (`onlyWhileActive`)
- Actualiza al `winner` si la oferta es válida.

---

### `showWinner() external view returns (address, uint)`
Retorna la dirección del `winner` y la `winningBid` **una vez finalizada la subasta**.

---

### `showBids() external view returns (address[] memory, uint[] memory)`
Retorna una lista con:
- Las direcciones de todos los ofertantes (`bidderList`)
- Sus ofertas válidas más altas (`currentAmount`)

---

### `withdrawExcess() external`
Permite a los participantes retirar el **excedente** que han depositado (ETH enviado que no forma parte de la oferta válida más alta).  
Ejemplo: si ofertaste 10 ETH pero tu oferta válida es de 7 ETH, puedes retirar 3 ETH.

---

### `finalizeAuction() external`
Solo puede ser ejecutada por el `owner`. Marca la subasta como `finalized` y emite el evento `AuctionFinalized`.

- Se puede ejecutar solo si ha pasado el tiempo de cierre (`block.timestamp >= auctionEndTime`)
- Libera los fondos a los perdedores (menos comisión)

---

### `withdrawCommission() external`
Permite al `owner` retirar una **comisión del 2%** sobre la `winningBid`, solo después de que la subasta haya sido finalizada.

---

### `timeLeft() external view returns (uint)`
Devuelve el tiempo restante (en segundos) antes de que finalice la subasta.

---

## 📢 Eventos

| Evento                  | Parámetros                                  | Descripción                                               |
|--------------------------|---------------------------------------------|-----------------------------------------------------------|
| `NewBid`                 | `address bidder, uint amount`               | Se emite cuando alguien hace una nueva oferta válida.     |
| `AuctionFinalized`       | `address winner, uint winningAmount`        | Se emite cuando el owner finaliza oficialmente la subasta.|
| `ExcessWithdrawn`        | `address participant, uint amount`          | Se emite cuando alguien retira su exceso.                 |
| `LoserRefunded`          | `address loser, uint refundedAmount`        | Se emite al reembolsar a un perdedor.                     |

---

## 💬 Cómo interactuar con el contrato

1. **Desplegar el contrato**  
   Proporciona la duración deseada en segundos al constructor (`_durationSeconds`).

2. **Hacer una oferta**  
   Llama a `bid()` enviando ETH. Asegúrate de ofertar al menos un 5% más que la la aferta actual  `winningBid`.

3. **Consultar el estado**  
   - Usa `showBids()` para ver todas las ofertas.
   - Usa `showWinner()` para ver el ganador (después de finalizar la subasta).

4. **Retirar excedente**  
   Llama a `withdrawExcess()` si has enviado más ETH de lo necesario.

5. **Finalizar subasta**  
   El `owner` llama a `finalizeAuction()` después del tiempo límite.

6. **Retirar comisión**  
   El `owner` llama a `withdrawCommission()` una vez finalizada la subasta.

---



## 🔐 Seguridad

- Las funciones críticas están protegidas con `modifier`s como `onlyOwner` y `onlyWhileActive`.
- Se valida cada oferta para prevenir manipulaciones.
- Los reembolsos y retiros están disponibles para proteger los fondos de los usuarios.
- Uso seguro de `call` para transferencias (aunque se recomienda revisión adicional para prevenir reentradas).

---

## 🧪 Licencia

MIT License ©️ 2025 - Herny Dev
