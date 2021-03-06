!----------------------------------------------------------------------------
! This file is part of DALES.
!
! DALES is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! DALES is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!
! Copyright 1993-2009 Delft University of Technology, Wageningen University, Utrecht University, KNMI
!----------------------------------------------------------------------------
!
!
module modsubgrid
implicit none
save
! private
public :: subgrid, initsubgrid,exitsubgrid
public :: ldelta, lmason,cf, Rigc,prandtl, cm, cn, ch1, ch2, ce1, ce2, ekm,ekh, sbdiss,sbshr,sbbuo

  !cstep: set default values
  !cstep: user has the option to change ldelta, cf, cn, and Rigc in namoptions

  logical :: ldelta   = .false. ! switch for subgrid length formulation (on/off)
  logical :: lmason   = .false. ! switch for decreased length scale near the surface
  real :: cf      = 2.5  !filter constant
  real :: Rigc    = 0.25 !critical Richardson number
  real :: Prandtl = 3
  real :: cm      = 0.12
  real :: cn      = 0.76
  real :: ch1     = 1.
  real :: ch2     = 2.
  real :: ce1     = 0.19
  real :: ce2     = 0.51

  real :: alpha_kolm   = 1.5     !factor in Kolmogorov expression for spectral energy
  real :: beta_kolm    = 1.      !factor in Kolmogorov relation for temperature spectrum

  real, allocatable :: ekm(:,:,:)  !  k-coefficient for momentum
  real, allocatable :: ekh(:,:,:)  !  k-coefficient for heat and q_tot
  real, allocatable :: sbdiss(:,:,:)!dissiation
  real, allocatable :: sbshr(:,:,:) !shear production
  real, allocatable :: sbbuo(:,:,:) !buoyancy production / destruction
  real, allocatable :: zlt(:,:,:)  !  filter width

contains
  subroutine initsubgrid
    use modglobal, only : ih,i1,jh,j1,k1,&
                          pi
    use modmpi, only    : myid
    implicit none

    real :: ceps, ch ,cs

    allocate(ekm(2-ih:i1+ih,2-jh:j1+jh,k1))
    allocate(ekh(2-ih:i1+ih,2-jh:j1+jh,k1))
    allocate(zlt(2-ih:i1+ih,2-jh:j1+jh,k1))
    allocate(sbdiss(2-ih:i1+ih,2-jh:j1+jh,k1))
    allocate(sbshr(2-ih:i1+ih,2-jh:j1+jh,k1))
    allocate(sbbuo(2-ih:i1+ih,2-jh:j1+jh,k1))


    cm = cf / (2. * pi) * (1.5*alpha_kolm)**(-1.5)

!     ch   = 2. * alpha_kolm / beta_kolm
    ch   = prandtl
    ch2  = ch-ch1

    ceps = 2. * pi / cf * (1.5*alpha_kolm)**(-1.5)
    ce1  = (cn**2)* (cm/Rigc - ch1*cm )
    ce2  = ceps - ce1

    cs   = (cm**3/ceps)**0.25   !smagorinsky constant, not used in model

    if (myid==0) then
      write (6,*) 'cf    = ',cf
      write (6,*) 'cm    = ',cm
      write (6,*) 'ch    = ',ch
      write (6,*) 'ch1   = ',ch1
      write (6,*) 'ch2   = ',ch2
      write (6,*) 'ceps  = ',ceps
      write (6,*) 'ceps1 = ',ce1
      write (6,*) 'ceps2 = ',ce2
      write (6,*) 'cs    = ',cs
      write (6,*) 'Rigc  = ',Rigc
    endif

!
  end subroutine initsubgrid
  subroutine subgrid

 ! Diffusion subroutines
! Thijs Heus, Chiel van Heerwaarden, 15 June 2007

    use modglobal, only : i1,ih,i2,j1,jh,j2,k1,nsv, lmoist
    use modfields, only : up,vp,wp,e12p,thl0,thlp,qt0,qtp,sv0,svp
    use modsurfdata,only : ustar,tstar,qstar,svstar
    implicit none
    integer n

    call closure
    call diffu(up)
    call diffv(vp)
    call diffw(wp)
    call diffe(e12p)
    call diffc(thl0,thlp,ustar,tstar)
    if (lmoist) call diffc( qt0, qtp,ustar,qstar)
    do n=1,nsv
      call diffc(sv0(:,:,:,n),svp(:,:,:,n),ustar,svstar(:,:,n))
    end do
    call sources
  end subroutine

  subroutine exitsubgrid
    implicit none
    deallocate(ekm,ekh,zlt,sbdiss,sbbuo,sbshr)
  end subroutine exitsubgrid

  subroutine closure

!-----------------------------------------------------------------|
!                                                                 |
!*** *closure*  calculates K-coefficients                         |
!                                                                 |
!      Hans Cuijpers   I.M.A.U.   06/01/1995                      |
!                                                                 |
!     purpose.                                                    |
!     --------                                                    |
!                                                                 |
!     All the K-closure factors are calculated.                   |
!                                                                 |
!     ekm(i,j,k) = k sub m : for velocity-closure                 |
!     ekh(i,j,k) = k sub h : for temperture-closure               |
!     ekh(i,j,k) = k sub h = k sub c : for concentration-closure  |
!                                                                 |
!     We will use the next model for these factors:               |
!                                                                 |
!     k sub m = 0.12 * l * sqrt(E)                                |
!                                                                 |
!     k sub h = k sub c = ( 1 + (2*l)/D ) * k sub m               |
!                                                                 |
!           where : l = mixing length  ( in model = z2 )          |
!                   E = subgrid energy                            |
!                   D = grid-size distance                        |
!                                                                 |
!**   interface.                                                  |
!     ----------                                                  |
!                                                                 |
!             *closure* is called from *program*.                 |
!                                                                 |
!-----------------------------------------------------------------|

  use modglobal, only : i1, j1,kmax,k1,ih,jh,i2,j2,delta,ekmin,grav, zf, fkar
  use modfields, only : dthvdz,e12m
  use modsurfdata,only : thvs
  use modmpi,    only : excjs
  implicit none


  integer :: i,j,k

!********************************************************************
!*********************************************************************

  do k=1,kmax
  do j=2,j1
  do i=2,i1
    if (ldelta .or. (dthvdz(i,j,k)<=0)) then
      zlt(i,j,k) = delta(k)
      if (lmason) zlt(i,j,k) = sqrt(1/(1/zlt(i,j,k)**2)+1/(fkar*zf(k))**2)
      ekm(i,j,k) = cm * zlt(i,j,k) * e12m(i,j,k)
      ekh(i,j,k) = (ch1 + ch2) * ekm(i,j,k)
    else

      zlt(i,j,k) = min(delta(k),cn*e12m(i,j,k)/sqrt(grav/thvs*abs(dthvdz(i,j,k))))
      if (lmason) zlt(i,j,k) = sqrt(1/(1/zlt(i,j,k)**2)+1/(fkar*zf(k))**2)

      ekm(i,j,k) = cm * zlt(i,j,k) * e12m(i,j,k)
      ekh(i,j,k) = (ch1 + ch2 * zlt(i,j,k)/delta(k)) * ekm(i,j,k)
    endif
  end do
  end do
  end do
  ekm(:,:,:) = max(ekm(:,:,:),ekmin)
  ekh(:,:,:) = max(ekh(:,:,:),ekmin)



!*************************************************************
!     Set cyclic boundary condition for K-closure factors.
!*************************************************************

  ekm(1, :,:) = ekm(i1,:,:)
  ekm(i2,:,:) = ekm(2, :,:)
  ekh(1, :,:) = ekh(i1,:,:)
  ekh(i2,:,:) = ekh(2, :,:)

  call excjs( ekm           , 2,i1,2,j1,1,k1,ih,jh)
  call excjs( ekh           , 2,i1,2,j1,1,k1,ih,jh)

  do j=1,j2
  do i=1,i2
    ekm(i,j,k1)  = ekm(i,j,kmax)
    ekh(i,j,k1)  = ekh(i,j,kmax)
  end do
  end do

  return
  end subroutine closure
  subroutine sources


!-----------------------------------------------------------------|
!                                                                 |
!*** *sources*                                                    |
!      calculates various terms from the subgrid TKE equation     |
!                                                                 |
!     Hans Cuijpers   I.M.A.U.     06/01/1995                     |
!                                                                 |
!     purpose.                                                    |
!     --------                                                    |
!                                                                 |
!      Subroutine sources calculates all other terms in the       |
!      subgrid energy equation, except for the diffusion terms.   |
!      These terms are calculated in subroutine diff.             |
!                                                                 |
!**   interface.                                                  |
!     ----------                                                  |
!                                                                 |
!     *sources* is called from *program*.                         |
!                                                                 |
!-----------------------------------------------------------------|

  use modglobal, only :i1,j1,kmax,delta,dx,dy,dxi,dyi,dzf,zf,dzh,grav
  use modfields, only : u0,v0,w0,e12m,e12p,dthvdz
  use modsurfdata,only :dudz,dvdz,thvs
  implicit none

  real    tdef2
  integer i,j,k,jm,jp,km,kp

  do k=2,kmax
  do j=2,j1
  do i=2,i1
    kp=k+1
    km=k-1
    jp=j+1
    jm=j-1

    tdef2 = 2. * ( &
             ((u0(i+1,j,k)-u0(i,j,k))   /dx         )**2    + &
             ((v0(i,jp,k)-v0(i,j,k))    /dy         )**2    + &
             ((w0(i,j,kp)-w0(i,j,k))    /dzf(k)     )**2    )

    tdef2 = tdef2 + 0.25 * ( &
              ((w0(i,j,kp)-w0(i-1,j,kp))  / dx     + &
               (u0(i,j,kp)-u0(i,j,k))     / dzh(kp)  )**2    + &
              ((w0(i,j,k)-w0(i-1,j,k))    / dx     + &
               (u0(i,j,k)-u0(i,j,km))     / dzh(k)   )**2    + &
              ((w0(i+1,j,k)-w0(i,j,k))    / dx     + &
               (u0(i+1,j,k)-u0(i+1,j,km)) / dzh(k)   )**2    + &
              ((w0(i+1,j,kp)-w0(i,j,kp))  / dx     + &
               (u0(i+1,j,kp)-u0(i+1,j,k)) / dzh(kp)  )**2    )

    tdef2 = tdef2 + 0.25 * ( &
              ((u0(i,jp,k)-u0(i,j,k))     / dy     + &
               (v0(i,jp,k)-v0(i-1,jp,k))  / dx        )**2    + &
              ((u0(i,j,k)-u0(i,jm,k))     / dy     + &
               (v0(i,j,k)-v0(i-1,j,k))    / dx        )**2    + &
              ((u0(i+1,j,k)-u0(i+1,jm,k)) / dy     + &
               (v0(i+1,j,k)-v0(i,j,k))    / dx        )**2    + &
              ((u0(i+1,jp,k)-u0(i+1,j,k)) / dy     + &
               (v0(i+1,jp,k)-v0(i,jp,k))  / dx        )**2    )

    tdef2 = tdef2 + 0.25 * ( &
              ((v0(i,j,kp)-v0(i,j,k))     / dzh(kp) + &
               (w0(i,j,kp)-w0(i,jm,kp))   / dy        )**2    + &
              ((v0(i,j,k)-v0(i,j,km))     / dzh(k)+ &
               (w0(i,j,k)-w0(i,jm,k))     / dy        )**2    + &
              ((v0(i,jp,k)-v0(i,jp,km))   / dzh(k)+ &
               (w0(i,jp,k)-w0(i,j,k))     / dy        )**2    + &
              ((v0(i,jp,kp)-v0(i,jp,k))   / dzh(kp) + &
               (w0(i,jp,kp)-w0(i,j,kp))   / dy        )**2    )


    sbshr(i,j,k)  = ekm(i,j,k)*tdef2/ ( 2*e12m(i,j,k))
    sbbuo(i,j,k)  = -ekh(i,j,k)*grav/thvs*dthvdz(i,j,k)/ ( 2*e12m(i,j,k))
    sbdiss(i,j,k) = - (ce1 + ce2*zlt(i,j,k)/delta(k)) * e12m(i,j,k)**2 /(2.*zlt(i,j,k))
  end do
  end do
  end do
!     ----------------------------------------------end i,j,k-loop

!     --------------------------------------------
!     special treatment for lowest full level: k=1
!     --------------------------------------------


  do j=2,j1
    jp=j+1
    jm=j-1
  do i=2,i1



! **  Calculate "shear" production term: tdef2  ****************

    tdef2 =  2. * ( &
            ((u0(i+1,j,1)-u0(i,j,1))*dxi)**2 &
          + ((v0(i,jp,1)-v0(i,j,1))*dyi)**2 &
          + ((w0(i,j,2)-w0(i,j,1))/dzf(1))**2   )

    tdef2 = tdef2 + ( 0.25*(w0(i+1,j,2)-w0(i-1,j,2))*dxi + &
                          dudz(i,j)   )**2

    tdef2 = tdef2 +   0.25 *( &
          ((u0(i,jp,1)-u0(i,j,1))*dyi+(v0(i,jp,1)-v0(i-1,jp,1))*dxi)**2 &
         +((u0(i,j,1)-u0(i,jm,1))*dyi+(v0(i,j,1)-v0(i-1,j,1))*dxi)**2 &
         +((u0(i+1,j,1)-u0(i+1,jm,1))*dyi+(v0(i+1,j,1)-v0(i,j,1))*dxi)**2 &
         +((u0(i+1,jp,1)-u0(i+1,j,1))*dyi+ &
                                 (v0(i+1,jp,1)-v0(i,jp,1))*dxi)**2   )

    tdef2 = tdef2 + ( 0.25*(w0(i,jp,2)-w0(i,jm,2))*dyi + &
                          dvdz(i,j)   )**2

! **  Include shear and buoyancy production terms and dissipation **

    sbshr(i,j,1)  = ekm(i,j,1)*tdef2/ ( 2*e12m(i,j,1))
    sbbuo(i,j,1)  = -ekh(i,j,1)*grav/thvs*dthvdz(i,j,1)/ ( 2*e12m(i,j,1))
    sbdiss(i,j,1) = - (ce1 + ce2*zlt(i,j,1)/delta(1)) * e12m(i,j,1)**2 /(2.*zlt(i,j,1))
  end do
  end do

  e12p(2:i1,2:j1,1:kmax) = e12p(2:i1,2:j1,1:kmax)+ &
            sbshr(2:i1,2:j1,1:kmax)+sbbuo(2:i1,2:j1,1:kmax)+sbdiss(2:i1,2:j1,1:kmax)

  return
  end subroutine sources

  subroutine diffc (putin,putout,ustar,vstar)

    use modglobal, only : i1,ih,i2,j1,jh,j2,k1,kmax,dx2i,dzf,dy2i,dzh
    implicit none

    real, intent(in)    :: putin(2-ih:i1+ih,2-jh:j1+jh,k1)
    real, intent(inout) :: putout(2-ih:i1+ih,2-jh:j1+jh,k1)
    real, intent(in)    :: ustar (i2,j2),vstar(i2,j2)

    integer i,j,k,jm,jp,km,kp

    do k=2,kmax
      kp=k+1
      km=k-1

      do j=2,j1
        jp=j+1
        jm=j-1

        do i=2,i1
          putout(i,j,k) = putout(i,j,k) &
                    +  0.5 *  ( &
                  ( (ekh(i+1,j,k)+ekh(i,j,k))*(putin(i+1,j,k)-putin(i,j,k)) &
                    -(ekh(i,j,k)+ekh(i-1,j,k))*(putin(i,j,k)-putin(i-1,j,k)))*dx2i &
                    + &
                  ( (ekh(i,jp,k)+ekh(i,j,k)) *(putin(i,jp,k)-putin(i,j,k)) &
                    -(ekh(i,j,k)+ekh(i,jm,k)) *(putin(i,j,k)-putin(i,jm,k)) )*dy2i &
                    + &
                  ( (dzf(kp)*ekh(i,j,k) + dzf(k)*ekh(i,j,kp)) &
                    *  (putin(i,j,kp)-putin(i,j,k)) / dzh(kp)**2 &
                    - &
                    (dzf(km)*ekh(i,j,k) + dzf(k)*ekh(i,j,km)) &
                    *  (putin(i,j,k)-putin(i,j,km)) / dzh(k)**2           )/dzf(k) &
                            )

        end do
      end do
    end do

    do j=2,j1
      do i=2,i1

        putout(i,j,1) = putout(i,j,1) &
                  + 0.5 * ( &
                ( (ekh(i+1,j,1)+ekh(i,j,1))*(putin(i+1,j,1)-putin(i,j,1)) &
                  -(ekh(i,j,1)+ekh(i-1,j,1))*(putin(i,j,1)-putin(i-1,j,1)) )*dx2i &
                  + &
                ( (ekh(i,j+1,1)+ekh(i,j,1))*(putin(i,j+1,1)-putin(i,j,1)) &
                  -(ekh(i,j,1)+ekh(i,j-1,1))*(putin(i,j,1)-putin(i,j-1,1)) )*dy2i &
                  + &
                ( (dzf(2)*ekh(i,j,1) + dzf(1)*ekh(i,j,2)) &
                  *  (putin(i,j,2)-putin(i,j,1)) / dzh(2)**2 &
                  - ustar(i,j) * vstar(i,j) *2.                        )/dzf(1) &
                          )

      end do
    end do

  end subroutine diffc



  subroutine diffe(putout)

    use modglobal, only : i1,ih,i2,j1,jh,j2,k1,kmax,dx2i,dzf,dy2i,dzh
    use modfields, only : e120
    implicit none

    real, intent(inout) :: putout(2-ih:i1+ih,2-jh:j1+jh,k1)
    integer             :: i,j,k,jm,jp,km,kp

    do k=2,kmax
      kp=k+1
      km=k-1

      do j=2,j1
        jp=j+1
        jm=j-1

        do i=2,i1

          putout(i,j,k) = putout(i,j,k) &
                  +  1.0 *  ( &
              ((ekm(i+1,j,k)+ekm(i,j,k))*(e120(i+1,j,k)-e120(i,j,k)) &
              -(ekm(i,j,k)+ekm(i-1,j,k))*(e120(i,j,k)-e120(i-1,j,k)))*dx2i &
                  + &
              ((ekm(i,jp,k)+ekm(i,j,k)) *(e120(i,jp,k)-e120(i,j,k)) &
              -(ekm(i,j,k)+ekm(i,jm,k)) *(e120(i,j,k)-e120(i,jm,k)) )*dy2i &
                  + &
              ((dzf(kp)*ekm(i,j,k) + dzf(k)*ekm(i,j,kp)) &
              *(e120(i,j,kp)-e120(i,j,k)) / dzh(kp)**2 &
              -(dzf(km)*ekm(i,j,k) + dzf(k)*ekm(i,j,km)) &
              *(e120(i,j,k)-e120(i,j,km)) / dzh(k)**2        )/dzf(k) &
                            )

        end do
      end do
    end do

  !     --------------------------------------------
  !     special treatment for lowest full level: k=1
  !     --------------------------------------------

    do j=2,j1
      do i=2,i1

        putout(i,j,1) = putout(i,j,1) + &
            ( (ekm(i+1,j,1)+ekm(i,j,1))*(e120(i+1,j,1)-e120(i,j,1)) &
              -(ekm(i,j,1)+ekm(i-1,j,1))*(e120(i,j,1)-e120(i-1,j,1)) )*dx2i &
            + &
            ( (ekm(i,j+1,1)+ekm(i,j,1))*(e120(i,j+1,1)-e120(i,j,1)) &
              -(ekm(i,j,1)+ekm(i,j-1,1))*(e120(i,j,1)-e120(i,j-1,1)) )*dy2i &
            + &
              ( (dzf(2)*ekm(i,j,1) + dzf(1)*ekm(i,j,2)) &
              *  (e120(i,j,2)-e120(i,j,1)) / dzh(2)**2              )/dzf(1)

      end do
    end do

  end subroutine diffe


  subroutine diffu (putout)

    use modglobal, only : i1,ih,i2,j1,jh,j2,k1,kmax,dxi,dx2i,dzf,dy,dyi,dy2i,dzh, cu,cv
    use modfields, only : u0,v0,w0
    use modsurfdata,only : ustar
    implicit none

    real, intent(inout) :: putout(2-ih:i1+ih,2-jh:j1+jh,k1)
    real                :: emmo,emom,emop,empo
    real                :: fu
    real                :: ucu, upcu
    integer             :: i,j,k,jm,jp,km,kp

    do k=2,kmax
      kp=k+1
      km=k-1

      do j=2,j1
        jp=j+1
        jm=j-1

        do i=2,i1

          emom = ( dzf(km) * ( ekm(i,j,k)  + ekm(i-1,j,k)  )  + &
                      dzf(k)  * ( ekm(i,j,km) + ekm(i-1,j,km) ) ) / &
                    ( 4.   * dzh(k) )

          emop = ( dzf(kp) * ( ekm(i,j,k)  + ekm(i-1,j,k)  )  + &
                      dzf(k)  * ( ekm(i,j,kp) + ekm(i-1,j,kp) ) ) / &
                    ( 4.   * dzh(kp) )

          empo = 0.25 * ( &
                  ekm(i,j,k)+ekm(i,jp,k)+ekm(i-1,jp,k)+ekm(i-1,j,k)  )

          emmo = 0.25 * ( &
                  ekm(i,j,k)+ekm(i,jm,k)+ekm(i-1,jm,k)+ekm(i-1,j,k)  )


          putout(i,j,k) = putout(i,j,k) &
                  + &
                  ( ekm(i,j,k)  * (u0(i+1,j,k)-u0(i,j,k)) &
                    -ekm(i-1,j,k)* (u0(i,j,k)-u0(i-1,j,k)) ) * 2. * dx2i &
                  + &
                  ( empo * ( (u0(i,jp,k)-u0(i,j,k))   *dyi &
                            +(v0(i,jp,k)-v0(i-1,jp,k))*dxi) &
                    -emmo * ( (u0(i,j,k)-u0(i,jm,k))   *dyi &
                            +(v0(i,j,k)-v0(i-1,j,k))  *dxi)   ) / dy &
                  + &
                  ( emop * ( (u0(i,j,kp)-u0(i,j,k))   /dzh(kp) &
                            +(w0(i,j,kp)-w0(i-1,j,kp))*dxi) &
                    -emom * ( (u0(i,j,k)-u0(i,j,km))   /dzh(k) &
                            +(w0(i,j,k)-w0(i-1,j,k))  *dxi)   ) /dzf(k)

        end do
      end do
    end do

  !     --------------------------------------------
  !     special treatment for lowest full level: k=1
  !     --------------------------------------------

    do j=2,j1
      jp = j+1
      jm = j-1

      do i=2,i1

        empo = 0.25 * ( &
              ekm(i,j,1)+ekm(i,jp,1)+ekm(i-1,jp,1)+ekm(i-1,j,1)  )

        emmo = 0.25 * ( &
              ekm(i,j,1)+ekm(i,jm,1)+ekm(i-1,jm,1)+ekm(i-1,j,1)  )

        emop = ( dzf(2) * ( ekm(i,j,1) + ekm(i-1,j,1) )  + &
                    dzf(1) * ( ekm(i,j,2) + ekm(i-1,j,2) ) ) / &
                  ( 4.   * dzh(2) )


        ucu   = 0.5*(u0(i,j,1)+u0(i+1,j,1))+cu

        if(ucu >= 0.) then
          upcu  = max(ucu,1.e-10)
        else
          upcu  = min(ucu,-1.e-10)
        end if


        fu = ( 0.5*( ustar(i,j)+ustar(i-1,j) ) )**2  * &
                upcu/sqrt(upcu**2  + &
                ((v0(i,j,1)+v0(i-1,j,1)+v0(i,jp,1)+v0(i-1,jp,1))/4.+cv)**2)

        putout(i,j,1) = putout(i,j,1) &
                + &
              ( ekm(i,j,1)  * (u0(i+1,j,1)-u0(i,j,1)) &
              -ekm(i-1,j,1)* (u0(i,j,1)-u0(i-1,j,1)) ) * 2. * dx2i &
                + &
              ( empo * ( (u0(i,jp,1)-u0(i,j,1))   *dyi &
                        +(v0(i,jp,1)-v0(i-1,jp,1))*dxi) &
              -emmo * ( (u0(i,j,1)-u0(i,jm,1))   *dyi &
                        +(v0(i,j,1)-v0(i-1,j,1))  *dxi)   ) / dy &
                + &
              ( emop * ( (u0(i,j,2)-u0(i,j,1))    /dzh(2) &
                        +(w0(i,j,2)-w0(i-1,j,2))  *dxi) &
                -fu   ) / dzf(1)

      end do
    end do

  end subroutine diffu


  subroutine diffv (putout)

    use modglobal, only : i1,ih,i2,j1,jh,j2,k1,kmax,dx,dxi,dx2i,dzf,dyi,dy2i,dzh, cu,cv
    use modfields, only : u0,v0,w0
    use modsurfdata,only : ustar

    implicit none

    real, intent(inout) :: putout(2-ih:i1+ih,2-jh:j1+jh,k1)
    real                :: emmo, eomm,eomp,epmo
    real                :: fv, vcv,vpcv
    integer             :: i,j,k,jm,jp,km,kp

    do k=2,kmax
      kp=k+1
      km=k-1

      do j=2,j1
        jp=j+1
        jm=j-1

        do i=2,i1

          eomm = ( dzf(km) * ( ekm(i,j,k)  + ekm(i,jm,k)  )  + &
                      dzf(k)  * ( ekm(i,j,km) + ekm(i,jm,km) ) ) / &
                    ( 4.   * dzh(k) )

          eomp = ( dzf(kp) * ( ekm(i,j,k)  + ekm(i,jm,k)  )  + &
                      dzf(k)  * ( ekm(i,j,kp) + ekm(i,jm,kp) ) ) / &
                    ( 4.   * dzh(kp) )

          emmo = 0.25  * ( &
                ekm(i,j,k)+ekm(i,jm,k)+ekm(i-1,jm,k)+ekm(i-1,j,k)  )

          epmo = 0.25  * ( &
                ekm(i,j,k)+ekm(i,jm,k)+ekm(i+1,jm,k)+ekm(i+1,j,k)  )


        putout(i,j,k) = putout(i,j,k) &
                + &
              ( epmo * ( (v0(i+1,j,k)-v0(i,j,k))   *dxi &
                        +(u0(i+1,j,k)-u0(i+1,jm,k))*dyi) &
                -emmo * ( (v0(i,j,k)-v0(i-1,j,k))   *dxi &
                        +(u0(i,j,k)-u0(i,jm,k))    *dyi)   ) / dx &
                + &
              (ekm(i,j,k) * (v0(i,jp,k)-v0(i,j,k)) &
              -ekm(i,jm,k)* (v0(i,j,k)-v0(i,jm,k))  ) * 2. * dy2i &
                + &
              ( eomp * ( (v0(i,j,kp)-v0(i,j,k))    /dzh(kp) &
                        +(w0(i,j,kp)-w0(i,jm,kp))  *dyi) &
                -eomm * ( (v0(i,j,k)-v0(i,j,km))    /dzh(k) &
                        +(w0(i,j,k)-w0(i,jm,k))    *dyi)   ) / dzf(k)

        end do
      end do
    end do

  !     --------------------------------------------
  !     special treatment for lowest full level: k=1
  !     --------------------------------------------

    do j=2,j1
      jp = j+1
      jm = j-1
      do i=2,i1

        emmo = 0.25 * ( &
              ekm(i,j,1)+ekm(i,jm,1)+ekm(i-1,jm,1)+ekm(i-1,j,1)  )

        epmo = 0.25  * ( &
              ekm(i,j,1)+ekm(i,jm,1)+ekm(i+1,jm,1)+ekm(i+1,j,1)  )

        eomp = ( dzf(2) * ( ekm(i,j,1) + ekm(i,jm,1)  )  + &
                    dzf(1) * ( ekm(i,j,2) + ekm(i,jm,2) ) ) / &
                  ( 4.   * dzh(2) )

        vcv   = 0.5*(v0(i,j,1)+v0(i,j+1,1))+cv
        if(vcv >= 0.) then
          vpcv  = max(vcv,1.e-10)
        else
          vpcv  = min(vcv,-1.e-10)
        end if


        fv    = ( 0.5*( ustar(i,j)+ustar(i,j-1) ) )**2  * &
                    vpcv/sqrt(vpcv**2  + &
                ((u0(i,j,1)+u0(i+1,j,1)+u0(i,jm,1)+u0(i+1,jm,1))/4.+cu)**2)

        putout(i,j,1) = putout(i,j,1) &
                  + &
                  ( epmo * ( (v0(i+1,j,1)-v0(i,j,1))   *dxi &
                            +(u0(i+1,j,1)-u0(i+1,jm,1))*dyi) &
                    -emmo * ( (v0(i,j,1)-v0(i-1,j,1))   *dxi &
                            +(u0(i,j,1)-u0(i,jm,1))    *dyi)   ) / dx &
                  + &
                ( ekm(i,j,1) * (v0(i,jp,1)-v0(i,j,1)) &
                  -ekm(i,jm,1)* (v0(i,j,1)-v0(i,jm,1))  ) * 2. * dy2i &
                  + &
                ( eomp * ( (v0(i,j,2)-v0(i,j,1))     /dzh(2) &
                          +(w0(i,j,2)-w0(i,jm,2))    *dyi) &
                  -fv   ) / dzf(1)

      end do
    end do

  end subroutine diffv



  subroutine diffw(putout)

    use modglobal, only : i1,ih,i2,j1,jh,j2,k1,kmax,dx,dxi,dx2i,dy,dyi,dy2i,dzf,dzh
    use modfields, only : u0,v0,w0
    implicit none

  !*****************************************************************

    real, intent(inout) :: putout(2-ih:i1+ih,2-jh:j1+jh,k1)
    real                :: emom, eomm, eopm, epom
    integer             :: i,j,k,jm,jp,km,kp

    do k=2,kmax
      kp=k+1
      km=k-1
      do j=2,j1
        jp=j+1
        jm=j-1
        do i=2,i1

          emom = ( dzf(km) * ( ekm(i,j,k)  + ekm(i-1,j,k)  )  + &
                      dzf(k)  * ( ekm(i,j,km) + ekm(i-1,j,km) ) ) / &
                    ( 4.   * dzh(k) )

          eomm = ( dzf(km) * ( ekm(i,j,k)  + ekm(i,jm,k)  )  + &
                      dzf(k)  * ( ekm(i,j,km) + ekm(i,jm,km) ) ) / &
                    ( 4.   * dzh(k) )

          eopm = ( dzf(km) * ( ekm(i,j,k)  + ekm(i,jp,k)  )  + &
                      dzf(k)  * ( ekm(i,j,km) + ekm(i,jp,km) ) ) / &
                    ( 4.   * dzh(k) )

          epom = ( dzf(km) * ( ekm(i,j,k)  + ekm(i+1,j,k)  )  + &
                      dzf(k)  * ( ekm(i,j,km) + ekm(i+1,j,km) ) ) / &
                    ( 4.   * dzh(k) )


          putout(i,j,k) = putout(i,j,k) &
                + &
                  ( epom * ( (w0(i+1,j,k)-w0(i,j,k))    *dxi &
                            +(u0(i+1,j,k)-u0(i+1,j,km)) /dzh(k) ) &
                    -emom * ( (w0(i,j,k)-w0(i-1,j,k))    *dxi &
                            +(u0(i,j,k)-u0(i,j,km))     /dzh(k) ))/dx &
                + &
                  ( eopm * ( (w0(i,jp,k)-w0(i,j,k))     *dyi &
                            +(v0(i,jp,k)-v0(i,jp,km))   /dzh(k) ) &
                    -eomm * ( (w0(i,j,k)-w0(i,jm,k))     *dyi &
                            +(v0(i,j,k)-v0(i,j,km))     /dzh(k) ))/dy &
                + &
                  ( ekm(i,j,k) * (w0(i,j,kp)-w0(i,j,k)) /dzf(k) &
                  -ekm(i,j,km)* (w0(i,j,k)-w0(i,j,km)) /dzf(km) ) * 2. &
                                                              / dzh(k)

        end do
      end do
    end do

  end subroutine diffw

end module
