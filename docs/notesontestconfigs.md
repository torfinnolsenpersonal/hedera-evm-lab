 Locations Where Time Delays Were Added for Solo                                                                                                          
                                                                                                                                                           
  1. Hardhat Configuration                                                                                                                                 
                                                                                                                                                           
  File: examples/hardhat/contract-smoke/hardhat.config.ts                                                                                                  
  - Solo network timeout: 120000ms (2x longer than Local Node's 60000ms)                                                                                   
                                                                                                                                                           
  2. All Test Files (6 total)                                                                                                                              
                                                                                                                                                           
  Each test file contains the same timing configuration pattern:                                                                                           
  ┌─────────────────────────────┬─────────────┐                                                                                                            
  │            File             │  Location   │                                                                                                            
  ├─────────────────────────────┼─────────────┤                                                                                                            
  │ test/Counter.test.ts        │ Lines 14-30 │                                                                                                            
  ├─────────────────────────────┼─────────────┤                                                                                                            
  │ test/HederaHTSTest.test.ts  │ Lines 14-22 │                                                                                                            
  ├─────────────────────────────┼─────────────┤                                                                                                            
  │ test/TestToken.test.ts      │ Lines 14-22 │                                                                                                            
  ├─────────────────────────────┼─────────────┤                                                                                                            
  │ test/PrecompileTest.test.ts │ Lines 14-22 │                                                                                                            
  ├─────────────────────────────┼─────────────┤                                                                                                            
  │ test/Factory.test.ts        │ Lines 14-22 │                                                                                                            
  ├─────────────────────────────┼─────────────┤                                                                                                            
  │ test/PayableTest.test.ts    │ Lines 14-22 │                                                                                                            
  └─────────────────────────────┴─────────────┘                                                                                                            
  Timing values:                                                                                                                                           
  ┌────────────────────┬────────────┬─────────┬─────────┬───────┐                                                                                          
  │     Parameter      │ Local Node │  Solo   │ Hardhat │ Ratio │                                                                                          
  ├────────────────────┼────────────┼─────────┼─────────┼───────┤                                                                                          
  │ defaultWaitMs      │ 500 ms     │ 2500 ms │ 0 ms    │ 5x    │                                                                                          
  ├────────────────────┼────────────┼─────────┼─────────┼───────┤                                                                                          
  │ intermediateWaitMs │ 300 ms     │ 1500 ms │ 0 ms    │ 5x    │                                                                                          
  ├────────────────────┼────────────┼─────────┼─────────┼───────┤                                                                                          
  │ timeout            │ 40-60s     │ 90-120s │ 10-20s  │ 2x    │                                                                                          
  └────────────────────┴────────────┴─────────┴─────────┴───────┘                                                                                          
  3. The waitForTx() Helper Function                                                                                                                       
                                                                                                                                                           
  Present in all test files (e.g., Counter.test.ts:81-95):                                                                                                 
  // Helper to wait for transaction and allow Hedera mirror node sync                                                                                      
  async function waitForTx(tx: any, customDelayMs?: number): Promise<any> {                                                                                
    const timing = getNetworkTiming();                                                                                                                     
    const delayMs = customDelayMs ?? timing.defaultWaitMs;                                                                                                 
    const receipt = await tx.wait();                                                                                                                       
                                                                                                                                                           
    // Allow time for Hedera mirror node to sync state                                                                                                     
    if (delayMs > 0) {                                                                                                                                     
      await new Promise(resolve => setTimeout(resolve, delayMs));                                                                                          
    }                                                                                                                                                      
    return receipt;                                                                                                                                        
  }                                                                                                                                                        
                                                                                                                                                           
  4. Shell Scripts                                                                                                                                         
                                                                                                                                                           
  - scripts/start-local-node.sh: sleep 2                                                                                                                   
  - scripts/start-solo.sh: sleep 5                                                                                                                         
  - scripts/run-all.sh: Multiple sleeps (10s, 30s, 5s)                                                                                                     
                                                                                                                                                           
  ---                                                                                                                                                      
  Synopsis: Why Solo Needs Extra Time                                                                                                                      
                                                                                                                                                           
  The Architectural Difference                                                                                                                             
                                                                                                                                                           
  Local Node uses a direct filesystem record stream parser:                                                                                                
  - The JSON-RPC relay reads transaction records directly from the consensus node's record stream files                                                    
  - This is essentially a "shortcut" where the relay parses the stream files from the filesystem                                                           
  - Result: Near-instant state availability after transaction confirmation                                                                                 
                                                                                                                                                           
  Solo uses the Mirror Node as an intermediary:                                                                                                            
  - Solo's architecture more closely mirrors production Hedera                                                                                             
  - After consensus, transactions must flow through the Mirror Node importer                                                                               
  - The Mirror Node ingests record streams, processes them, and exposes them via REST/gRPC APIs                                                            
  - The JSON-RPC relay queries the Mirror Node to get state information                                                                                    
  - Result: Additional latency while waiting for Mirror Node to sync                                                                                       
                                                                                                                                                           
  The Flow Comparison                                                                                                                                      
                                                                                                                                                           
  Local Node:                                                                                                                                              
    Consensus Node → Record Stream File → [Direct Parse] → JSON-RPC Relay                                                                                  
                                           (filesystem)                                                                                                    
                                                                                                                                                           
  Solo (Production-like):                                                                                                                                  
    Consensus Node → Record Stream → Mirror Node Importer → Mirror Node DB → JSON-RPC Relay                                                                
                                     (network hop)          (query)                                                                                        
                                                                                                                                                           
  Why This Matters for Tests                                                                                                                               
                                                                                                                                                           
  When a test:                                                                                                                                             
  1. Sends a transaction                                                                                                                                   
  2. Waits for receipt                                                                                                                                     
  3. Immediately queries state                                                                                                                             
                                                                                                                                                           
  On Local Node: The state is available almost instantly because of direct filesystem parsing.                                                             
                                                                                                                                                           
  On Solo: The state may not be visible yet because the Mirror Node hasn't finished ingesting and indexing the transaction record. Without the extra delay,
   tests fail with stale state reads.                                                                                                                      
                                                                                                                                                           
  The 5x multiplier (500ms → 2500ms) provides enough buffer for the Mirror Node sync cycle to complete before the test reads state.               
