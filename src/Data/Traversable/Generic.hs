{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}

-- |
-- This module generates implementations of the 'traverse' operation which
-- make it possible for GHC to optimize away the GHC.Generics value
-- representation.
module Data.Traversable.Generic
  (
  -- * Generic operations
  genericTraverse,
  -- * Implementation details
  GTraversable
  ) where

import Control.Applicative
import Data.Foldable (Foldable(..))
import Data.Functor.Kan.Rift (Rift(..))
import Data.Functor.Yoneda (Yoneda(..), liftYoneda, lowerYoneda)
import Data.Traversable (Traversable(..), fmapDefault, foldMapDefault)
import GHC.Generics

-- NOTE: genericTraversal an gtraverse must be explicitly marked
-- for inlining as they need to inline across module boundaries
-- for GHC to optimize away the generics representation. The other
-- functions don't *need* to be marked for inlining because GHC
-- does figure it out, but it's better to be explicit about our
-- intention here than to rely on the optimizer any more than
-- we already are.

-- | Implementation of 'traverse' for any instance of 'Generic1'.
genericTraverse ::
  (Generic1 t, GTraversable (Rep1 t), Applicative f) =>
  (a -> f b) -> t a -> f (t b)
genericTraverse f x = lowerYoneda (pure to1 <*>^ gtraverse f (from1 x))
{-# INLINE genericTraverse #-}


-- | The 'GTraversable' class has a method for traversing a generic
-- structure. This function is not quite the same as 'traverse' because
-- it uses a particular transformation on the underlying applicative functor.
--
-- 'gtraverse' implements a traversal of the generic representation
-- of a value. By using 'Rift' we ensure that the calls to
-- '<*>' will all be associated to the left. When combined with 'Yoneda'
-- these left-assoicated '<*>' will enable all of the 'fmap' calls
-- accumulated along the way to also collect on the left and fuse.
--
-- All of this fusion will put the code in a form which the GHC optimizer will
-- be able to optimize away all signs of the Generics representation. The
-- resulting traversals will look like this:
--
-- @
-- 'pure' Constructor0
-- 'pure' Constructor1 '<*>' f a
-- 'pure' Constructor3 '<*>' f a '<*>' f b '<*>' f c
-- @
class GTraversable t where
  gtraverse :: Applicative f => (a -> f b) -> t a -> Rift (Yoneda f) (Yoneda f) (t b)

instance GTraversable f => GTraversable (M1 i c f) where
  gtraverse f (M1 x) = fmap M1 (gtraverse f x)
  {-# INLINE gtraverse #-}

instance (GTraversable f, GTraversable g) => GTraversable (f :+: g) where
  gtraverse f (L1 x) = fmap L1 (gtraverse f x)
  gtraverse f (R1 x) = fmap R1 (gtraverse f x)
  {-# INLINE gtraverse #-}

instance (GTraversable f, GTraversable g) => GTraversable (f :*: g) where
  gtraverse f (x :*: y) = (:*:) <$> gtraverse f x <*> gtraverse f y
  {-# INLINE gtraverse #-}

instance GTraversable U1 where
  gtraverse _ _ = pure U1
  {-# INLINE gtraverse #-}

instance GTraversable V1 where
  gtraverse _ v = v `seq` error "GTraversal/V1: gtraverse"
  {-# INLINE gtraverse #-}

instance GTraversable (K1 i a) where
  gtraverse _ (K1 x) = pure (K1 x)
  {-# INLINE gtraverse #-}

instance GTraversable Par1 where
  gtraverse f (Par1 x) = fmap Par1 (liftRiftYoneda (f x))
  {-# INLINE gtraverse #-}

instance Traversable f => GTraversable (Rec1 f) where
  gtraverse f (Rec1 x) = fmap Rec1 (liftRiftYoneda (traverse f x))
  {-# INLINE gtraverse #-}

------------------------------------------------------------------------
-- Utilities for constructing and destructing Rift and Yoneda
------------------------------------------------------------------------

liftRiftYoneda :: Applicative f => f a -> Rift (Yoneda f) (Yoneda f) a
liftRiftYoneda fa = Rift (`yap` fa)
{-# INLINE liftRiftYoneda #-}

yap :: Applicative f => Yoneda f (a -> b) -> f a -> Yoneda f b
yap (Yoneda k) fa = Yoneda (\ab_r -> k (ab_r .) <*> fa )
{-# INLINE yap #-}

-- | Run function for 'Rift'
(<*>^) :: f (a -> b) -> Rift f g a -> g b
x <*>^ Rift y = y x
infixl 4 <*>^
{-# INLINE (<*>^) #-}
