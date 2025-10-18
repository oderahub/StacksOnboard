import { Cl } from '@stacks/transactions'
import { describe, expect, it, beforeEach } from 'vitest'

const accounts = simnet.getAccounts()
const deployer = accounts.get('deployer')!
const user1 = accounts.get('wallet_1')!
const user2 = accounts.get('wallet_2')!

describe('EasyStack Contract Tests', () => {
  beforeEach(() => {
    // Reset state for each test
    simnet.setEpoch('3.0')
  })

  describe('Initialization', () => {
    it('should initialize admin successfully', () => {
      const { result } = simnet.callPublicFn('easystack', 'init', [], deployer)
      expect(result).toBeOk(Cl.bool(true))
    })

    it('should not allow double initialization', () => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
      const { result } = simnet.callPublicFn('easystack', 'init', [], deployer)
      expect(result).toBeErr(Cl.uint(106))
    })

    it('should return correct admin after initialization', () => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
      const { result } = simnet.callReadOnlyFn('easystack', 'get-admin', [], deployer)
      expect(result).toBeSome(Cl.principal(deployer))
    })
  })

  describe('Admin Functions', () => {
    beforeEach(() => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
    })

    it('should allow admin to set reward rate', () => {
      const { result } = simnet.callPublicFn(
        'easystack',
        'set-reward-rate',
        [Cl.uint(15)],
        deployer
      )
      expect(result).toBeOk(Cl.uint(15))
    })

    it('should not allow reward rate above denominator', () => {
      const { result } = simnet.callPublicFn(
        'easystack',
        'set-reward-rate',
        [Cl.uint(101)],
        deployer
      )
      expect(result).toBeErr(Cl.uint(102))
    })

    it('should not allow non-admin to set reward rate', () => {
      const { result } = simnet.callPublicFn('easystack', 'set-reward-rate', [Cl.uint(15)], user1)
      expect(result).toBeErr(Cl.uint(103))
    })
  })

  describe('User Registration', () => {
    beforeEach(() => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
    })

    it('should allow user to register', () => {
      const { result } = simnet.callPublicFn('easystack', 'register-user', [], user1)
      expect(result).toBeOk(Cl.bool(true))
    })

    it('should not allow duplicate registration', () => {
      simnet.callPublicFn('easystack', 'register-user', [], user1)
      const { result } = simnet.callPublicFn('easystack', 'register-user', [], user1)
      expect(result).toBeErr(Cl.uint(101))
    })

    it('should check if user is registered', () => {
      simnet.callPublicFn('easystack', 'register-user', [], user1)
      const { result } = simnet.callReadOnlyFn(
        'easystack',
        'is-registered',
        [Cl.principal(user1)],
        deployer
      )
      expect(result).toStrictEqual(Cl.bool(true))
    })

    it('should initialize user info correctly', () => {
      simnet.callPublicFn('easystack', 'register-user', [], user1)
      const { result } = simnet.callReadOnlyFn(
        'easystack',
        'get-user-info',
        [Cl.principal(user1)],
        deployer
      )
      expect(result).toBeSome(
        Cl.tuple({
          'stx-stacked': Cl.uint(0),
          'total-rewards': Cl.uint(0),
          'quest-points': Cl.uint(0)
        })
      )
    })
  })

  describe('Staking STX', () => {
    beforeEach(() => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
      simnet.callPublicFn('easystack', 'register-user', [], user1)
    })

    it('should allow user to stack STX', () => {
      const { result } = simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(1000)], user1)
      expect(result).toBeOk(Cl.uint(1000))
    })

    it('should not allow stacking zero amount', () => {
      const { result } = simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(0)], user1)
      expect(result).toBeErr(Cl.uint(102))
    })

    it('should not allow unregistered user to stack', () => {
      const { result } = simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(1000)], user2)
      expect(result).toBeErr(Cl.uint(100))
    })

    it('should accumulate stacked amounts', () => {
      simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(1000)], user1)
      simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(500)], user1)

      const { result } = simnet.callReadOnlyFn(
        'easystack',
        'get-user-info',
        [Cl.principal(user1)],
        deployer
      )
      expect(result).toBeSome(
        Cl.tuple({
          'stx-stacked': Cl.uint(1500),
          'total-rewards': Cl.uint(0),
          'quest-points': Cl.uint(0)
        })
      )
    })
  })

  describe('Reward Rate Management', () => {
    beforeEach(() => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
    })

    it('should get current reward rate', () => {
      const { result } = simnet.callReadOnlyFn('easystack', 'get-reward-rate', [], deployer)
      expect(result).toStrictEqual(Cl.uint(10))
    })

    it('should update reward rate', () => {
      simnet.callPublicFn('easystack', 'set-reward-rate', [Cl.uint(25)], deployer)
      const { result } = simnet.callReadOnlyFn('easystack', 'get-reward-rate', [], deployer)
      expect(result).toStrictEqual(Cl.uint(25))
    })
  })

  describe('Multiple Users', () => {
    beforeEach(() => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
    })

    it('should handle multiple users independently', () => {
      // Register both users
      simnet.callPublicFn('easystack', 'register-user', [], user1)
      simnet.callPublicFn('easystack', 'register-user', [], user2)

      // Stack different amounts
      simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(1000)], user1)
      simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(2000)], user2)

      // Check user1 info
      const result1 = simnet.callReadOnlyFn(
        'easystack',
        'get-user-info',
        [Cl.principal(user1)],
        deployer
      )
      expect(result1.result).toBeSome(
        Cl.tuple({
          'stx-stacked': Cl.uint(1000),
          'total-rewards': Cl.uint(0),
          'quest-points': Cl.uint(0)
        })
      )

      // Check user2 info
      const result2 = simnet.callReadOnlyFn(
        'easystack',
        'get-user-info',
        [Cl.principal(user2)],
        deployer
      )
      expect(result2.result).toBeSome(
        Cl.tuple({
          'stx-stacked': Cl.uint(2000),
          'total-rewards': Cl.uint(0),
          'quest-points': Cl.uint(0)
        })
      )
    })
  })

  describe('Claim State Tracking', () => {
    beforeEach(() => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
      simnet.callPublicFn('easystack', 'register-user', [], user1)
    })

    it('should initialize claim state on registration', () => {
      const { result } = simnet.callReadOnlyFn(
        'easystack',
        'get-claim-info',
        [Cl.principal(user1)],
        deployer
      )
      expect(result).toBeSome(
        Cl.tuple({
          'last-claim-height': Cl.uint(0),
          'claim-count': Cl.uint(0)
        })
      )
    })
  })

  describe('Error Handling', () => {
    beforeEach(() => {
      simnet.callPublicFn('easystack', 'init', [], deployer)
    })

    it('should require registration before stacking', () => {
      const { result } = simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(1000)], user1)
      expect(result).toBeErr(Cl.uint(100)) // ERR-NOT-REGISTERED
    })

    it('should reject zero amount staking', () => {
      simnet.callPublicFn('easystack', 'register-user', [], user1)
      const { result } = simnet.callPublicFn('easystack', 'stack-stx', [Cl.uint(0)], user1)
      expect(result).toBeErr(Cl.uint(102)) // ERR-INVALID-AMOUNT
    })

    it('should prevent unauthorized admin actions', () => {
      const { result } = simnet.callPublicFn('easystack', 'set-reward-rate', [Cl.uint(20)], user1)
      expect(result).toBeErr(Cl.uint(103)) // ERR-NOT-AUTHORIZED
    })
  })
})
