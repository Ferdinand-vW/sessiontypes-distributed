{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE FlexibleInstances     #-}
-- | Provides instances for `Session` of `IxMonadThrow`, `IxMonadCatch` and `IxMonadMask`.
--
-- These instances should behave no differently from the corresponding `MonadThrow`, `MonadCatch` and `MonadMask` instances for `Process`.
-- For more documentation please visit "Control.Monad.Catch"
--
-- The reason that the instances are placed in a separate module is to avoid a circular dependency of the modules.
-- 
-- The instances require evaluation of the sessions, therefore "Control.Distributed.Session.Eval" should be imported.
--
-- However that module imports "Control.Distributed.Session.Session". Placing these instances in this module would then require importing "Control.Distributed.Session.Eval" causing a circular dependency.
--
-- Note that these instances are already exported by "Control.Distributed.Session", such that this module should need no explicit import.
module Control.Distributed.Session.Exception where

import qualified Control.SessionTypes.Indexed as I
import           Control.Monad.Catch as C
import           Control.SessionTypes.Indexed
import           Control.SessionTypes.Codensity (rep)
import           Control.Distributed.Session.Session
import           Control.Distributed.Session.Eval (evalSessionEq)
import           Control.Distributed.Process

instance IxMonadThrow Session s where
  throwM e = Session $ \_ -> rep $ lift $ C.throwM e

instance IxMonadCatch Session s where
  catch sess h = Session $ \si ->
    let p = evalSessionEq sess
    in rep $ lift $ C.catch p (\e -> evalSessionEq (h e))

instance IxMonadMask Session s where
  mask s = Session $ \si ->
    rep $ lift $ C.mask $ \restore -> evalSessionEq (s $ liftRestore restore)
    where liftRestore :: (Process a -> Process a) -> Session s s a -> Session s s a
          liftRestore restore = \s -> Session $ \si -> rep $ lift $ restore $ evalSessionEq s
          
  uninterruptibleMask s = Session $ \si ->
    rep $ lift $ C.uninterruptibleMask $ \restore -> evalSessionEq (s $ liftRestore restore)
    where liftRestore :: (Process a -> Process a) -> Session s s a -> Session s s a
          liftRestore restore = \s -> Session $ \si -> rep $ lift $ restore $ evalSessionEq s