{-# LANGUAGE RebindableSyntax         #-}
{-# LANGUAGE TypeOperators            #-}
{-# LANGUAGE DataKinds                #-}
{-# LANGUAGE TypeFamilies             #-}
{-# LANGUAGE ScopedTypeVariables      #-}
-- | This module defines two interpreters for mapping the Cloud Haskell semantics to the constructors of `STTerm`.
module Control.Distributed.Session.Eval (
  evalSession,
  evalSessionEq,
  evalSessionEq'
) where

import           Control.SessionTypes
import           Control.SessionTypes.Indexed
import           Control.SessionTypes.Types
import           Control.Distributed.Session.STChannel
import           Control.Distributed.Session.Session

import qualified Control.Distributed.Process                as P
import           Control.Distributed.Process.Serializable
import           Data.Proxy (Proxy(..))

import qualified Prelude as PL

-- Some type synonyms for the send and receive ports used in this module
type SendPortST s = RemoveRecv (SendInsInt s)
type RecvPortST s = RemoveSend (RecvInsInt s)
type MapRecvPortST xs = MapRemoveSend (MapRecvInsInt xs)

-- | This function unpacks a `Session` to a `STTerm` using a given `SessionInfo`. 
--
-- It then evaluates the `STTerm` by mapping Cloud Haskell semantics to each constructor of `STTerm`.
--
-- The function relies on that there exists another session (on a different process) that is also being evaluated (using evalSession)
-- and acts as the dual the session that function is now evaluating.
--
-- The underlying communication method is a session typed channel (`STChannelT`). There should be no interference from other processes, unless
-- you go through the effort of sharing the send port.
evalSession :: forall s r a. HasConstraint Serializable s => Session s r a -> SessionInfo -> P.Process a
evalSession sess si =
      let st = runSession sess (Just si)
          (sp', rp') = toSTChanBi (utchan si) (Proxy :: Proxy (SendInsInt s)) (Proxy :: Proxy (RecvInsInt s))
      in PL.fmap fst $ runSTChannelT (eval st) (sp', rp')

eval :: HasConstraint Serializable s => STTerm P.Process s r a -> 
        STChannelT P.Process (SendPortST s :*: RecvPortST s) 
                           (SendPortST r :*: RecvPortST r) 
                           a
eval (Send a r) = do
  sendSTChanM a
  eval r
eval (Recv r) = do
  a <- recvSTChanM
  eval (r a)
eval s@(Sel1 _) = unFoldSelect 0 s
eval s@(Sel2 _) = unFoldSelect 0 s
eval o@(OffS _ _) = do
  x <- recvSTChanM
  unFoldOffer x o
eval o@(OffZ _) = do
  x <- recvSTChanM
  unFoldOffer x o
eval (Rec s) = do
  recChanM
  eval s
eval (Weaken s) = do
  wkChanM
  eval s
eval (Var s) = do
  varChanM
  eval s
eval (Lift m) = do
  st <- lift m
  eval st
eval (Ret a) = do
  return a

-- | Similar to `evalSession`, except for that it does not evaluate session typed actions.
--
-- Only returns and lifted computations are evaluated. This also means that there does not need to be a
-- dual session that is evaluated on a different process.
--
-- It also assumes that `SessionInfo` is not used. Use `evalSessionEq'` if this is not the case.
evalSessionEq :: Session s s a -> P.Process a
evalSessionEq sess = do
  let st = runSession sess Nothing
  evalST st
  where
    evalST :: STTerm P.Process s s a -> P.Process a
    evalST (Ret a) = PL.return a
    evalST (Lift m) = m PL.>>= evalST

-- | Same as `evalSessionEq`, but you may now provide a `SessionInfo`.
evalSessionEq' :: Session s s a -> SessionInfo -> P.Process a
evalSessionEq' sess si = do
  let st = runSession sess (Just si)
  evalST st
  where
    evalST :: STTerm P.Process s s a -> P.Process a
    evalST (Ret a) = PL.return a
    evalST (Lift m) = m PL.>>= evalST

unFoldSelect :: (s ~ 'Cap ctx (Sel xs), HasConstraint Serializable s) => 
                Int -> STTerm P.Process s r a -> 
                STChannelT P.Process (SendPortST s :*: RecvPortST s) 
                                   (SendPortST r :*: RecvPortST r) 
                                  a
unFoldSelect k (Sel1 s) = sel1ChanM >> sendSTChanM k >> eval s
unFoldSelect k (Sel2 s) = sel2ChanM >> unFoldSelect (k + 1) s

unFoldOffer :: (s ~ 'Cap ctx (Off xs), HasConstraint Serializable s) => Int -> STTerm P.Process s r a -> 
               STChannelT P.Process (SendPortST s :*: 'Cap (MapRecvPortST ctx) (Off (MapRecvPortST xs))) 
                                  (SendPortST r :*: RecvPortST r) 
                                  a
unFoldOffer _ (OffZ s)    = off1ChanM >> eval s
unFoldOffer 0 (OffS s _)  = off1ChanM >> eval s
unFoldOffer n (OffS _ xs) = off2ChanM >> unFoldOffer (n - 1) xs

type family MapSendInsInt ss where
  MapSendInsInt '[] = '[]
  MapSendInsInt (s ': xs) = (Int :!> SendInsIntST s) ': MapSendInsInt xs

type family MapSendInsInt' ss where
  MapSendInsInt' '[] = '[]
  MapSendInsInt' (s ': xs) = SendInsIntST s ': MapSendInsInt' xs

type family SendInsInt c where
  SendInsInt ('Cap ctx s) = 'Cap (MapSendInsInt' ctx) (SendInsIntST s)

type family SendInsIntCtx ctx where
  SendInsIntCtx '[] = '[]
  SendInsIntCtx (s ': ctx) = SendInsIntST s ': SendInsIntCtx ctx

type family SendInsIntST s where
  SendInsIntST (a :!> r) = a :!> (SendInsIntST r)
  SendInsIntST (a :?> r) = a :?> SendInsIntST r
  SendInsIntST (Sel xs) = Sel (MapSendInsInt xs)
  SendInsIntST (Off xs) = Off (MapSendInsInt' xs)
  SendInsIntST (R s) = R (SendInsIntST s)
  SendInsIntST (Wk s) = Wk (SendInsIntST s)
  SendInsIntST V = V
  SendInsIntST Eps = Eps

type family MapRecvInsInt ss where
  MapRecvInsInt '[] = '[]
  MapRecvInsInt (s ': xs) = RecvInsIntST s ': MapRecvInsInt xs

type family RecvInsInt c where
  RecvInsInt ('Cap ctx s) = 'Cap (MapRecvInsInt ctx) (RecvInsIntST s)

type family RecvInsIntST s where
  RecvInsIntST (a :!> r) = a :!> RecvInsIntST r
  RecvInsIntST (a :?> r) = a :?> RecvInsIntST r
  RecvInsIntST (Sel xs) = Sel (MapRecvInsInt xs)
  RecvInsIntST (Off xs) = Int :?> (Off (MapRecvInsInt xs)) 
  RecvInsIntST (R s) = R (RecvInsIntST s)
  RecvInsIntST (Wk s) = Wk (RecvInsIntST s)
  RecvInsIntST V = V
  RecvInsIntST Eps = Eps