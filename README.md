# Bitcoin Time-Lock Escrow with SPL Condition

A sophisticated Bitcoin time-locked escrow service built on the Stacks blockchain, featuring Secret Preimage Lock (SPL) conditions for secure, trustless transactions.

## 🚀 Overview

This smart contract implements a dual-condition escrow system where funds are locked until both a Bitcoin block height threshold is reached AND a secret preimage is revealed. This provides enhanced security and flexibility for time-sensitive transactions.

### Key Features

- **Bitcoin Time-Lock**: Uses Bitcoin burn block heights for precise timing
- **SPL Condition**: Secret Preimage Lock requiring SHA256 hash verification
- **Dual Recovery**: Both time-based expiry and secret-based unlocking
- **Emergency Controls**: Contract owner intervention capabilities
- **Comprehensive Validation**: Input sanitization and state verification
- **Event Transparency**: All STX transfers logged on-chain

## 🔧 Smart Contract Architecture

### Core Data Structure

```clarity
{
  sender: principal,           // Escrow creator
  recipient: principal,        // Intended beneficiary  
  amount: uint,               // STX amount locked
  bitcoin-unlock-height: uint, // Bitcoin block height threshold
  secret-hash: (buff 32),     // SHA256 hash of secret
  is-claimed: bool,           // Recipient claimed status
  is-refunded: bool,          // Sender refund status
  created-at-height: uint     // Creation block height
}
```

### Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u100 | ERR-NOT-AUTHORIZED | Unauthorized access attempt |
| u101 | ERR-ESCROW-NOT-FOUND | Escrow ID doesn't exist |
| u102 | ERR-ESCROW-ALREADY-EXISTS | Escrow ID collision |
| u103 | ERR-AMOUNT-MUST-BE-POSITIVE | Zero or negative amount |
| u104 | ERR-INVALID-BITCOIN-HEIGHT | Invalid block height |
| u105 | ERR-ESCROW-LOCKED | Escrow conditions not met |
| u106 | ERR-BITCOIN-HEIGHT-NOT-REACHED | Time lock active |
| u107 | ERR-INVALID-SECRET | Secret preimage mismatch |
| u108 | ERR-ESCROW-ALREADY-CLAIMED | Double-spend prevention |
| u109 | ERR-ESCROW-EXPIRED | Time window expired |
| u110 | ERR-INSUFFICIENT-BALANCE | Insufficient STX balance |

## 📋 Public Functions

### Core Functions

#### `create-escrow`
```clarity
(create-escrow (recipient principal) (amount uint) (blocks-ahead uint) (secret-hash (buff 32)))
```
Creates a new escrow with specified parameters.

**Parameters:**
- `recipient`: Address that can claim the escrow
- `amount`: STX amount to lock (in microSTX)
- `blocks-ahead`: Bitcoin blocks until unlock
- `secret-hash`: SHA256 hash of the secret

**Returns:** `(ok escrow-id)` on success

#### `claim-escrow`
```clarity
(claim-escrow (escrow-id uint) (secret (buff 32)))
```
Claims an escrow by providing the correct secret preimage.

**Requirements:**
- Must be called by the recipient
- Bitcoin unlock height must be reached
- Secret must hash to stored secret-hash
- Escrow must not be already claimed/refunded

#### `refund-escrow`
```clarity
(refund-escrow (escrow-id uint))
```
Refunds an escrow to the sender after expiry.

**Requirements:**
- Must be called by the sender
- Bitcoin unlock height must be reached
- Escrow must not be already claimed/refunded

### Administrative Functions

#### `emergency-cancel-escrow`
```clarity
(emergency-cancel-escrow (escrow-id uint))
```
Emergency cancellation by contract owner (before unlock height).

### Query Functions

#### `get-escrow`
```clarity
(get-escrow (escrow-id uint))
```
Returns complete escrow data or none.

#### `get-escrow-status`
```clarity
(get-escrow-status (escrow-id uint))
```
Returns escrow status summary with computed fields.

#### `get-contract-stats`
```clarity
(get-contract-stats)
```
Returns contract-wide statistics and current state.

#### `can-claim-escrow` / `can-refund-escrow`
```clarity
(can-claim-escrow (escrow-id uint))
(can-refund-escrow (escrow-id uint))
```
Check if escrow is eligible for claim/refund.

## 🛠️ Development Setup

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Stacks smart contract development tool
- [Node.js](https://nodejs.org/) - For TypeScript tests
- [Git](https://git-scm.com/) - Version control

### Installation

```bash
# Clone the repository
git clone https://github.com/hischilling/Bitcoin-Time-Lock-Escrow-with-SPL-Condition.git
cd Bitcoin-Time-Lock-Escrow-with-SPL-Condition

# Check contract syntax
clarinet check

# Run tests
clarinet test
```

### Project Structure

```
├── Clarinet.toml                 # Clarinet configuration
├── contracts/
│   └── Bitcoin-time-lock-escrow-with-spl-condition.clar
├── tests/
│   └── Bitcoin-time-lock-escrow-with-spl-condition_test.ts
├── settings/
│   ├── Devnet.toml
│   ├── Testnet.toml
│   └── Mainnet.toml
└── README.md
```

## 🧪 Testing

The project includes comprehensive TypeScript tests covering:

- ✅ Valid escrow creation with parameter validation
- ✅ Successful claims with correct secret preimage
- ✅ Proper refund mechanisms after time-lock expiry
- ✅ Authorization checks preventing unauthorized access
- ✅ Emergency cancellation by contract owner
- ✅ Contract statistics and monitoring capabilities
- ✅ Error conditions and edge cases

```bash
# Run all tests
clarinet test

# Check contract syntax
clarinet check
```

## 🔒 Security Features

### Time-Lock Security
- Uses Bitcoin burn block heights for tamper-resistant timing
- Prevents premature claims before unlock height
- Automatic expiry mechanism for unclaimed escrows

### Secret Preimage Lock (SPL)
- SHA256 hash verification for secret validation
- Prevents unauthorized claims without correct preimage
- Cryptographic proof of secret knowledge

### Access Control
- Strict authorization checks for all functions
- Sender/recipient role enforcement
- Contract owner emergency powers with limited scope

### Double-Spend Protection
- State tracking prevents multiple claims/refunds
- Atomic state updates with transaction rollback
- Comprehensive validation before state changes

## 📊 Use Cases

### 1. Atomic Swaps
- Cross-chain trading with Bitcoin timing
- Secret reveals ensure fair exchange
- Time limits prevent indefinite locks

### 2. Conditional Payments
- Release payments upon secret disclosure
- Time-bounded service agreements
- Escrow for digital goods delivery

### 3. Trustless Betting
- Sports betting with reveal deadlines
- Prediction markets with time windows
- Fair random number generation

### 4. Digital Asset Trading
- NFT trading with time limits
- Token swaps with conditions
- DeFi protocol integrations

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Clarity best practices
- Add comprehensive tests for new features
- Update documentation for API changes
- Ensure all tests pass before submitting

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Guide](https://book.clarity-lang.org/)
- [Clarinet Documentation](https://docs.hiro.so/smart-contracts/clarinet)
- [Stacks Explorer](https://explorer.stacks.co/)

## ⚠️ Disclaimer

This smart contract is provided as-is for educational and development purposes. Thoroughly test and audit before using in production environments. The authors are not responsible for any loss of funds or security vulnerabilities.

---

**Built with ❤️ on Stacks**
