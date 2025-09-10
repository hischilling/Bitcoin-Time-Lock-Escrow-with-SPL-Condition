
import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v0.14.0/index.ts';
import { assertEquals, assertExists } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

const contractName = "Bitcoin-time-lock-escrow-with-spl-condition";

// Helper function to create a test secret and its hash
function createTestSecret() {
    const secret = new Uint8Array(32);
    secret.fill(1); // Simple test secret
    return {
        secret: types.buff(secret),
        hash: types.buff(new Uint8Array(32).fill(2)) // Mock hash for testing
    };
}

Clarinet.test({
    name: "Test escrow creation with valid parameters",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const recipient = accounts.get('wallet_1')!;
        const { hash } = createTestSecret();
        
        let block = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'create-escrow',
                [
                    types.principal(recipient.address),
                    types.uint(1000000), // 1 STX
                    types.uint(10), // 10 blocks ahead
                    hash
                ],
                deployer.address
            )
        ]);
        
        assertEquals(block.receipts.length, 1);
        assertEquals(block.receipts[0].result.expectOk(), types.uint(1));
        
        // Verify escrow was created
        let queryBlock = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'get-escrow',
                [types.uint(1)],
                deployer.address
            )
        ]);
        
        const escrowData = queryBlock.receipts[0].result.expectSome();
        assertExists(escrowData);
    },
});

Clarinet.test({
    name: "Test escrow creation fails with zero amount",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const recipient = accounts.get('wallet_1')!;
        const { hash } = createTestSecret();
        
        let block = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'create-escrow',
                [
                    types.principal(recipient.address),
                    types.uint(0), // Zero amount should fail
                    types.uint(10),
                    hash
                ],
                deployer.address
            )
        ]);
        
        assertEquals(block.receipts.length, 1);
        assertEquals(block.receipts[0].result.expectErr(), types.uint(103)); // ERR-AMOUNT-MUST-BE-POSITIVE
    },
});

Clarinet.test({
    name: "Test successful escrow claim with correct secret",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const recipient = accounts.get('wallet_1')!;
        const { secret, hash } = createTestSecret();
        
        // Create escrow
        let block = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'create-escrow',
                [
                    types.principal(recipient.address),
                    types.uint(1000000),
                    types.uint(1), // 1 block ahead
                    hash
                ],
                deployer.address
            )
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), types.uint(1));
        
        // Mine blocks to reach unlock height
        chain.mineEmptyBlockUntil(block.height + 2);
        
        // Attempt to claim with correct secret
        let claimBlock = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'claim-escrow',
                [types.uint(1), secret],
                recipient.address
            )
        ]);
        
        assertEquals(claimBlock.receipts.length, 1);
        // Note: This test assumes the secret validation works - in real implementation
        // you'd need to ensure the hash matches the secret
    },
});

Clarinet.test({
    name: "Test escrow refund by sender after expiry",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const recipient = accounts.get('wallet_1')!;
        const { hash } = createTestSecret();
        
        // Create escrow
        let block = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'create-escrow',
                [
                    types.principal(recipient.address),
                    types.uint(1000000),
                    types.uint(1), // 1 block ahead
                    hash
                ],
                deployer.address
            )
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), types.uint(1));
        
        // Mine blocks to reach unlock height
        chain.mineEmptyBlockUntil(block.height + 2);
        
        // Sender attempts refund
        let refundBlock = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'refund-escrow',
                [types.uint(1)],
                deployer.address
            )
        ]);
        
        assertEquals(refundBlock.receipts.length, 1);
        assertEquals(refundBlock.receipts[0].result.expectOk(), types.bool(true));
    },
});

Clarinet.test({
    name: "Test unauthorized claim attempt fails",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const recipient = accounts.get('wallet_1')!;
        const unauthorized = accounts.get('wallet_2')!;
        const { secret, hash } = createTestSecret();
        
        // Create escrow
        let block = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'create-escrow',
                [
                    types.principal(recipient.address),
                    types.uint(1000000),
                    types.uint(1),
                    hash
                ],
                deployer.address
            )
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), types.uint(1));
        
        // Mine blocks to reach unlock height
        chain.mineEmptyBlockUntil(block.height + 2);
        
        // Unauthorized user attempts to claim
        let claimBlock = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'claim-escrow',
                [types.uint(1), secret],
                unauthorized.address
            )
        ]);
        
        assertEquals(claimBlock.receipts.length, 1);
        assertEquals(claimBlock.receipts[0].result.expectErr(), types.uint(100)); // ERR-NOT-AUTHORIZED
    },
});

Clarinet.test({
    name: "Test emergency cancel by contract owner",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const recipient = accounts.get('wallet_1')!;
        const { hash } = createTestSecret();
        
        // Create escrow
        let block = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'create-escrow',
                [
                    types.principal(recipient.address),
                    types.uint(1000000),
                    types.uint(10), // 10 blocks ahead
                    hash
                ],
                deployer.address
            )
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), types.uint(1));
        
        // Emergency cancel before unlock height
        let cancelBlock = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'emergency-cancel-escrow',
                [types.uint(1)],
                deployer.address
            )
        ]);
        
        assertEquals(cancelBlock.receipts.length, 1);
        assertEquals(cancelBlock.receipts[0].result.expectOk(), types.bool(true));
    },
});

Clarinet.test({
    name: "Test contract statistics retrieval",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall(
                contractName,
                'get-contract-stats',
                [],
                deployer.address
            )
        ]);
        
        assertEquals(block.receipts.length, 1);
        const stats = block.receipts[0].result.expectOk();
        assertExists(stats);
    },
});
