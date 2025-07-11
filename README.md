# Tokenized Community Transportation Coordination System

A decentralized platform for coordinating shared transportation within communities using Clarity smart contracts on the Stacks blockchain.

## Overview

This system consists of five interconnected smart contracts that facilitate efficient, safe, and fair community transportation coordination:

1. **Ride Sharing Contract** - Connects neighbors for efficient commute coordination
2. **Route Optimization Contract** - Plans shared transportation paths and timing
3. **Cost Sharing Contract** - Calculates fair expense distribution among participants
4. **Safety Verification Contract** - Validates driver credentials and vehicle condition
5. **Schedule Synchronization Contract** - Coordinates pickup times and locations

## Features

### Ride Sharing
- Create and join ride requests
- Match riders with drivers based on routes
- Token-based incentive system
- Reputation tracking

### Route Optimization
- Define and optimize transportation routes
- Calculate efficient pickup sequences
- Distance and time estimation
- Route sharing and coordination

### Cost Sharing
- Fair cost calculation based on distance and participants
- Automatic payment distribution
- Gas cost splitting
- Transparent fee structure

### Safety Verification
- Driver credential verification
- Vehicle safety checks
- Insurance validation
- Safety rating system

### Schedule Synchronization
- Coordinated pickup and drop-off times
- Real-time schedule updates
- Conflict resolution
- Automated notifications

## Token Economics

The system uses a native token (TRANSPORT) for:
- Incentivizing drivers
- Rewarding reliable participants
- Paying for rides
- Staking for safety verification

## Contract Architecture

Each contract operates independently while maintaining data consistency through standardized data structures and events.

## Getting Started

### Prerequisites
- Clarinet CLI
- Node.js and npm
- Stacks wallet

### Installation

1. Clone the repository
2. Install dependencies: \`npm install\`
3. Run tests: \`npm test\`
4. Deploy contracts: \`clarinet deploy\`

## Usage

### For Riders
1. Create a ride request with origin, destination, and preferred time
2. Browse available rides or wait for matches
3. Join a ride and contribute to cost sharing
4. Rate the experience after completion

### For Drivers
1. Register vehicle and credentials through safety verification
2. Create ride offers with route and capacity
3. Accept ride requests from matched riders
4. Receive tokens as compensation

## Testing

Run the test suite with:
\`\`\`
npm test
\`\`\`

Tests cover:
- Contract functionality
- Edge cases
- Security scenarios
- Integration flows

## Security Considerations

- All contracts include access controls
- Input validation on all public functions
- Protection against common attack vectors
- Audit-ready code structure

## Contributing

Please read the PR details file for contribution guidelines.

## License

MIT License - see LICENSE file for details
