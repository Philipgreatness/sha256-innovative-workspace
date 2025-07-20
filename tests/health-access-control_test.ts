import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Health Access Control: User Identity Registration",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const alice = accounts.get('wallet_1')!;

        // Attempt identity registration
        let block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'register-identity', [], alice.address)
        ]);

        // Verify successful registration
        assertEquals(block.receipts[0].result, '(ok true)');

        // Prevent duplicate registration
        block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'register-identity', [], alice.address)
        ]);

        assertEquals(block.receipts[0].result, '(err u2)');
    }
});

Clarinet.test({
    name: "Health Access Control: Endpoint Registration",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const alice = accounts.get('wallet_1')!;

        // First register identity
        let block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'register-identity', [], alice.address)
        ]);

        // Register device endpoint
        block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'register-endpoint', ['device-123', 'smartwatch'], alice.address)
        ]);

        assertEquals(block.receipts[0].result, '(ok true)');

        // Prevent duplicate device registration
        block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'register-endpoint', ['device-123', 'smartwatch'], alice.address)
        ]);

        assertEquals(block.receipts[0].result, '(err u4)');

        // Prevent endpoint registration without identity
        const bob = accounts.get('wallet_2')!;
        block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'register-endpoint', ['device-456', 'fitness-tracker'], bob.address)
        ]);

        assertEquals(block.receipts[0].result, '(err u3)');
    }
});

Clarinet.test({
    name: "Health Access Control: Consumer Authorization",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const healthcare = accounts.get('wallet_1')!;

        // Authorize healthcare provider
        let block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'authorize-consumer', [healthcare.address, 'hospital'], deployer.address)
        ]);

        assertEquals(block.receipts[0].result, '(ok true)');

        // Prevent duplicate authorization
        block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'authorize-consumer', [healthcare.address, 'hospital'], deployer.address)
        ]);

        assertEquals(block.receipts[0].result, '(err u7)');
    }
});

Clarinet.test({
    name: "Health Access Control: Domain Access Management",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const alice = accounts.get('wallet_1')!;
        const healthProvider = accounts.get('wallet_2')!;

        // Setup: Register identity and authorize consumer
        let block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'register-identity', [], alice.address),
            Tx.contractCall('health-access-control', 'authorize-consumer', [healthProvider.address, 'hospital'], deployer.address)
        ]);

        // Grant domain access with expiration
        block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'grant-domain-access', [healthProvider.address, 'cardiac-metrics', types.some(500)], alice.address)
        ]);

        assertEquals(block.receipts[0].result, '(ok true)');

        // Verify access granted
        let result = chain.callReadOnlyFn('health-access-control', 'check-data-access', [alice.address, healthProvider.address, 'cardiac-metrics'], alice.address);
        assertEquals(result.result, '(ok true)');

        // Revoke access
        block = chain.mineBlock([
            Tx.contractCall('health-access-control', 'revoke-domain-access', [healthProvider.address, 'cardiac-metrics'], alice.address)
        ]);

        assertEquals(block.receipts[0].result, '(ok true)');

        // Verify access revoked
        result = chain.callReadOnlyFn('health-access-control', 'check-data-access', [alice.address, healthProvider.address, 'cardiac-metrics'], alice.address);
        assertEquals(result.result, '(ok false)');
    }
});