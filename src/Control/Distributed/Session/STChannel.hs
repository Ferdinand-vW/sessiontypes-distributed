{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE TypeOperators             #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE StandaloneDeriving        #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE KindSignatures            #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE TypeFamilies              #-}
-- | Defines a session typed channel as a wrapper over the typed channel from Cloud Haskell
--
-- We define a session typed channel to overcome the limitation of a typed channel that can only send and receive messages of a single type.
--
-- Underneath we actually do the same, and make use of `unsafeCoerce` to coerce a value's type to that described in the session typed.
--
-- Session types do not entirely guarantee safety of using `unsafeCoerce`. One can use the same session typed send port over and over again,
-- while the correpsonding receive port might progress through the session type resulting in a desync of types between the send and receive port.
--
-- It is for this reason recommended to always make use of `STChannelT` that always progresses the session type of a port after a session typed action.
module Control.Distributed.Session.STChannel (
  -- * Data types
  Message(..),
  STSendPort(..),
  STReceivePort(..),
  -- * Type synonyms
  STChan,
  STChanBi,
  UTChan,
  -- * Create
  newSTChan,
  newSTChanBi,
  newUTChan,
  toSTChan,
  toSTChanBi,
  sendProxy,
  recvProxy,
  -- * Usage
  sendSTChan,
  recvSTChan,
  STSplit(..),
  STRec(..),
  -- * Channel transformer
  STChannelT(..),
  sendSTChanM,
  recvSTChanM,
  sel1ChanM,
  sel2ChanM,
  off1ChanM,
  off2ChanM,
  recChanM,
  wkChanM,
  varChanM,
  epsChanM
) where

import qualified Control.SessionTypes.Indexed                     as IM
import           Control.SessionTypes.Types

import qualified Control.Distributed.Process              as P
import           Control.Distributed.Process.Serializable

import qualified Data.ByteString.Lazy                     as BSL
import           Data.Binary
import           Data.Typeable
import           Data.Kind (Type)
import           Unsafe.Coerce

-- | Basic message type that existentially quantifies the content of the message
data Message = forall a. Serializable a => Message a deriving Typeable

instance Binary Message where
  put (Message msg) = put $ BSL.toChunks (encode msg)
  get = (Message . BSL.fromChunks) <$> get

-- | Session typed send port as a wrapper over SendPort Message. It is parameterized with a capability/sessiontype.
data STSendPort    (l :: Cap Type) = STSendPort    (P.SendPort    Message)
-- | Session typed receive port as a wrapper over ReceivePort Message. It is parameterized with a capability/sessiontype.
data STReceivePort (l :: Cap Type) = STReceivePort (P.ReceivePort Message)

-- | Type synonym for a session typed channel given a single session type
--
-- This removes recv session types from the given session type as it is passed to the send port type
--
-- Also removes send session types from the given session type as it is passed to the receive port type
type STChan s     = (STSendPort (RemoveRecv s), STReceivePort (RemoveSend s))
-- | Same as `STChan`, but it is given a session type for the send port type and a separate session type for the receive port type
type STChanBi s r = (STSendPort (RemoveRecv s), STReceivePort (RemoveSend r))
-- | Unsession typed typed channel
--
-- It is essentially just a typed channel that is parameterized with `Message`.
--
-- We can carry around this type in `Session`, but not a `STChan`.
type UTChan       = (P.SendPort Message, P.ReceivePort Message)

-- | Creates a new session typed channel given a single session type
newSTChan :: Proxy s -> P.Process (STChan s)
newSTChan _ = do
    (s, r) <- P.newChan
    return $ (STSendPort s, STReceivePort r)

-- | Creates a new session typed channel given separate session types for the send port and receive port
newSTChanBi :: Proxy s -> Proxy r -> P.Process (STChanBi s r)
newSTChanBi _ _ = do
    (s, r) <- P.newChan
    return $ (STSendPort s, STReceivePort r)

-- | Creates an unsession typed channel
newUTChan :: P.Process UTChan
newUTChan = P.newChan

-- | Converts an unsession typed channel to a session typed channel
toSTChan :: UTChan -> Proxy s -> STChan s
toSTChan (sport, rport) _ = (STSendPort sport, STReceivePort rport)

-- | Converts an unsession typed channel to a session typed channel
toSTChanBi :: UTChan -> Proxy s -> Proxy r -> STChanBi s r
toSTChanBi (sport, rport) _ _ = (STSendPort sport, STReceivePort rport)

-- | Converts a session typed send port into a Proxy
sendProxy :: STSendPort s -> Proxy s
sendProxy _ = Proxy

-- | Converts a session typed receive port into a Proxy
recvProxy :: STReceivePort s -> Proxy s
recvProxy _ = Proxy

-- | Sends a message using a session typed send port
sendSTChan :: Serializable a => STSendPort ('Cap ctx (a :!> l)) -> a -> P.Process (STSendPort ('Cap ctx l))
sendSTChan (STSendPort s) a = do
    P.sendChan s $ Message a
    return $ STSendPort s 

-- | Receives a message using a session typed receive port
recvSTChan :: Serializable a => STReceivePort ('Cap ctx (a :?> l)) -> P.Process (a, STReceivePort ('Cap ctx l))
recvSTChan (STReceivePort p) = do
    (Message b) <- P.receiveChan p
    return (unsafeCoerce b, STReceivePort p)

-- | Type class that defines combinators for branching on a session typed port
class STSplit (m :: Cap Type -> Type) where
    -- | select the first branch of a selection using the given port
    sel1Chan :: m ('Cap ctx (Sel (s ': xs)))      -> m ('Cap ctx s)
    -- | select the second branch of a selection using the given port
    sel2Chan :: m ('Cap ctx (Sel (s ': t ': xs))) -> m ('Cap ctx (Sel (t ': xs)))
    -- | select the first branch of an offering using the given port
    off1Chan :: m ('Cap ctx (Off (s ': xs)))      -> m ('Cap ctx s)
    -- | select the second branch of an offering using the given port
    off2Chan :: m ('Cap ctx (Off (s ': t ': xs))) -> m ('Cap ctx (Off (t ': xs)))

instance STSplit STSendPort where
  sel1Chan (STSendPort s) = STSendPort s
  sel2Chan (STSendPort s) = STSendPort s
  off1Chan (STSendPort s) = STSendPort s
  off2Chan (STSendPort s) = STSendPort s

instance STSplit STReceivePort where
  sel1Chan (STReceivePort s) = STReceivePort s
  sel2Chan (STReceivePort s) = STReceivePort s
  off1Chan (STReceivePort s) = STReceivePort s
  off2Chan (STReceivePort s) = STReceivePort s

-- | Type class for recursion on a session typed port
class STRec (m :: Cap Type -> Type) where
  recChan :: m ('Cap       ctx  (R s))  -> m ('Cap (s ': ctx) s)
  wkChan ::  m ('Cap (t ': ctx) (Wk s)) -> m ('Cap       ctx  s)
  varChan :: m ('Cap (s ': ctx)  V)     -> m ('Cap (s ': ctx) s)

instance STRec STSendPort where
  recChan (STSendPort s) = STSendPort s
  wkChan  (STSendPort s) = STSendPort s
  varChan (STSendPort s) = STSendPort s

instance STRec STReceivePort where
  recChan (STReceivePort s) = STReceivePort s
  wkChan  (STReceivePort s) = STReceivePort s
  varChan (STReceivePort s) = STReceivePort s

-- | Indexed monad transformer that is indexed by two products of session types
--
-- This monad also acts as a state monad that whose state is defined by a session typed channel and dependent on the indexing of the monad.
data STChannelT m (p :: Prod Type) (q :: Prod Type) a = STChannelT { 
  runSTChannelT :: (      (STSendPort (Left p), STReceivePort (Right p)) -> 
                  m (a, (STSendPort (Left q), STReceivePort (Right q)))) 
  }

instance Monad m => IM.IxFunctor (STChannelT m) where
  fmap f (STChannelT g) = STChannelT $ \c -> g c >>= \(a, c') -> return (f a, c')

instance Monad m => IM.IxApplicative (STChannelT m) where
  pure = IM.return
  (STChannelT f) <*> (STChannelT g) = STChannelT $ \c -> f c >>= \(f', c') -> g c' >>= \(a, c'') -> return (f' a, c'')

instance Monad m => IM.IxMonad (STChannelT m) where
  return a = STChannelT $ \c -> return (a, c)
  (STChannelT f) >>= g = STChannelT $ \c -> f c >>= \(a, c') -> runSTChannelT (g a) c'

instance Monad m => IM.IxMonadT STChannelT m where
  lift m = STChannelT $ \c -> m >>= \a -> return (a, c)

-- | Send a message
--
-- Only the session type of the send port needs to be adjusted
sendSTChanM :: Serializable a => a -> STChannelT P.Process ('Cap ctx (a :!> l) :*: r) ('Cap ctx l :*: r) ()
sendSTChanM a = STChannelT $ \(sp, rp) -> sendSTChan sp a >>= \sp' -> return ((), (sp', rp))

-- | receive a message
--
-- Only the session type of the receive port needs to be adjusted
recvSTChanM :: Serializable a => STChannelT P.Process (l :*: ('Cap ctx (a :?> r))) (l :*: 'Cap ctx r) a
recvSTChanM = STChannelT $ \(sp, rp) -> recvSTChan rp >>= \(a, rp') -> return (a, (sp, rp'))

-- | select the first branch of a selection
--
-- Both ports are now adjusted. This is similarly so for the remaining combinators.
sel1ChanM :: STChannelT P.Process ('Cap lctx (Sel (l ': ls)) :*: ('Cap rctx (Sel (r ': rs)))) ('Cap lctx l :*: 'Cap rctx r) ()
sel1ChanM = STChannelT $ \(sp, rp) -> return ((), (sel1Chan sp, sel1Chan rp))

-- | select the second branch of a selection
sel2ChanM :: STChannelT P.Process ('Cap lctx (Sel (s1 ': t1 ': xs1)) :*: 'Cap rctx (Sel (s2 ': t2 ': xs2))) ('Cap lctx (Sel (t1 ': xs1)) :*: 'Cap rctx (Sel (t2 ': xs2))) ()
sel2ChanM = STChannelT $ \(sp, rp) -> return ((), (sel2Chan sp, sel2Chan rp))

-- | select the first branch of an offering
off1ChanM :: STChannelT P.Process ('Cap lctx (Off (l ': ls)) :*: ('Cap rctx (Off (r ': rs)))) ('Cap lctx l :*: 'Cap rctx r) ()
off1ChanM = STChannelT $ \(sp, rp) -> return ((), (off1Chan sp, off1Chan rp))

-- | select the second branch of an offering
off2ChanM :: STChannelT P.Process ('Cap lctx (Off (s1 ': t1 ': xs1)) :*: 'Cap rctx (Off (s2 ': t2 ': xs2))) ('Cap lctx (Off (t1 ': xs1)) :*: 'Cap rctx (Off (t2 ': xs2))) ()
off2ChanM = STChannelT $ \(sp, rp) -> return ((), (off2Chan sp, off2Chan rp))

-- | delimit scope of recursion
recChanM :: STChannelT P.Process ('Cap sctx (R s) :*: 'Cap rctx (R r)) ('Cap (s ': sctx) s :*: 'Cap (r ': rctx) r) ()
recChanM = STChannelT $ \(sp, rp) -> return ((), (recChan sp, recChan rp))

-- | weaken scope of recursion
wkChanM :: STChannelT P.Process ('Cap (t ': sctx) (Wk s) :*: 'Cap (k ': rctx) (Wk r)) ('Cap sctx s :*: 'Cap rctx r) ()
wkChanM = STChannelT $ \(sp, rp) -> return ((), (wkChan sp, wkChan rp)) 

-- | recursion variable (recurse here)
varChanM :: STChannelT P.Process (('Cap (s ': sctx) V) :*: ('Cap (r ': rctx) V)) ('Cap (s ': sctx) s :*: 'Cap (r ': rctx) r) ()
varChanM = STChannelT $ \(sp, rp) -> return ((), (varChan sp, varChan rp))

-- | ports are no longer usable
epsChanM :: STChannelT P.Process ('Cap ctx Eps :*: 'Cap ctx Eps) ('Cap ctx Eps :*: 'Cap ctx Eps) ()
epsChanM = STChannelT $ \utchan -> return ((), utchan)