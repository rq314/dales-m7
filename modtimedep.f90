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
!
!       ----------------------------------------------------------------
!
!*    module *modtimedep* prescribed surface fluxes and LS forcings
!*                    at certain times
!*
!*            Roel Neggers    KNMI    01-05-2001
!
!       ----------------------------------------------------------------

module modtimedep


implicit none
private
public :: inittimedep, timedep,ltimedep,exittimedep

save
! switches for timedependent surface fluxes and large scale forcings
  logical       :: ltimedep     = .false. !Overall switch, input in namoptions
  logical       :: ltimedepz    = .true.  !Switch for large scale forcings
  logical       :: ltimedepsurf = .true.  !Switch for surface fluxes

  integer, parameter    :: kflux = 100
  integer, parameter    :: kls   = 100
  real, allocatable     :: timeflux (:)
  real, allocatable     :: wqsurft  (:)
  real, allocatable     :: wtsurft  (:)
  real, allocatable     :: thlst    (:)
  real, allocatable     :: qtst     (:)
  real, allocatable     :: pst      (:)

  real, allocatable     :: timels  (:)
  real, allocatable     :: ugt     (:,:)
  real, allocatable     :: vgt     (:,:)
  real, allocatable     :: wflst   (:,:)
  real, allocatable     :: dqtdxlst(:,:)
  real, allocatable     :: dqtdylst(:,:)
  real, allocatable     :: dqtdtlst(:,:)
  real, allocatable     :: thlpcart(:,:)
  real, allocatable     :: thlproft(:,:)
  real, allocatable     :: qtproft (:,:)



contains
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  subroutine inittimedep
    use modmpi,   only :myid,my_real,mpi_logical,mpierr,comm3d
    use modglobal,only :ifnamopt,fname_options,dtmax, btime,cexpnr,k1,kmax,ifinput,runtime
    use modsurfdata,only:ps,qts,wqsurf,wtsurf,thls
    use modtimedepsv, only : inittimedepsv
    implicit none

    character (80):: chmess
    character (1) :: chmess1
    integer :: k,t, ierr
    real :: dummyr
    real, allocatable, dimension (:) :: height
    if (.not. ltimedep) return

    allocate(height(k1))
    allocate(timeflux (0:kflux))
    allocate(wqsurft  (kflux))
    allocate(wtsurft  (kflux))
    allocate(timels  (0:kls))
    allocate(ugt     (k1,kls))
    allocate(vgt     (k1,kls))
    allocate(wflst   (k1,kls))
    allocate(dqtdxlst(k1,kls))
    allocate(dqtdylst(k1,kls))
    allocate(dqtdtlst(k1,kls))
    allocate(thlpcart(k1,kls))
    allocate(thlproft(k1,kls))
    allocate(qtproft(k1,kls))
    allocate(thlst   (0:kls))
    allocate(qtst    (0:kls))
    allocate(pst    (0:kls))

    timeflux = 0
    wqsurft  = wqsurf
    wtsurft  = wtsurf
    thlst    = thls
    qtst     = qts
    pst      = ps

    timels   = 0
    ugt      = 0
    vgt      = 0
    wflst    = 0
    dqtdxlst = 0
    dqtdylst = 0
    dqtdtlst = 0
    thlpcart = 0
    thlproft = 0
    qtproft  = 0

    if (myid==0) then

!    --- load lsforcings---


      open(ifinput,file='ls_flux.inp.'//cexpnr)
      read(ifinput,'(a80)') chmess
      write(6,*) chmess
      read(ifinput,'(a80)') chmess
      write(6,*) chmess
      read(ifinput,'(a80)') chmess
      write(6,*) chmess

      timeflux = 0
      timels   = 0


!      --- load fluxes---

      t    = 0
      ierr = 0
      do while (timeflux(t)< (runtime+btime))
        t=t+1
        read(ifinput,*, iostat = ierr) timeflux(t), wtsurft(t), wqsurft(t),thlst(t),qtst(t),pst(t)
        write(*,'(f8.1,6e12.4)') timeflux(t), wtsurft(t), wqsurft(t),thlst(t),qtst(t),pst(t)
        if (ierr < 0) then
            stop 'STOP: No time dependend data for end of run (surface fluxes)'
        end if
      end do
      if(timeflux(1)>(runtime+btime)) then
         write(6,*) 'Time dependent surface variables do not change before end of'
         write(6,*) 'simulation. --> only large scale forcings'
         ltimedepsurf=.false.
      endif
! flush to the end of fluxlist
      do while (ierr ==0)
        read (ifinput,*,iostat=ierr) dummyr
      end do
!     ---load large scale forcings----

      t = 0

      do while (timels(t) < (runtime+btime))
        t = t + 1
        chmess1 = "#"
        ierr = 1 ! not zero
        do while (.not.(chmess1 == "#" .and. ierr ==0)) !search for the next line consisting of "# time", from there onwards the profiles will be read
          read(ifinput,*,iostat=ierr) chmess1,timels(t)
          if (ierr < 0) then
            stop 'STOP: No time dependend data for end of run'
          end if
        end do
        write (*,*) 'timels = ',timels(t)
        do k=1,kmax
          read (ifinput,*) &
            height  (k)  , &
            ugt     (k,t), &
            vgt     (k,t), &
            wflst   (k,t), &
            dqtdxlst(k,t), &
            dqtdylst(k,t), &
            dqtdtlst(k,t), &
            thlpcart(k,t)
        end do
        do k=kmax,1,-1
          write (6,'(3f7.1,5e12.4)') &
            height  (k)  , &
            ugt     (k,t), &
            vgt     (k,t), &
            wflst   (k,t), &
            dqtdxlst(k,t), &
            dqtdylst(k,t), &
            dqtdtlst(k,t), &
            thlpcart(k,t)
        end do
      end do

      if ((timels(1) > (runtime+btime)) .or. (timeflux(1) > (runtime+btime))) then
        write(6,*) 'Time dependent large scale forcings sets in after end of simulation -->'
        write(6,*) '--> only time dependent surface variables'
        ltimedepz=.false.
      end if

      close(ifinput)

    end if

    call MPI_BCAST(timeflux(1:kflux),kflux,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(wtsurft          ,kflux,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(wqsurft          ,kflux,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(thlst            ,kflux,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(qtst             ,kflux,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(pst              ,kflux,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(timels(1:kls)    ,kls,MY_REAL  ,0,comm3d,mpierr)
    call MPI_BCAST(ugt              ,kmax*kls,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(vgt              ,kmax*kls,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(wflst            ,kmax*kls,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(dqtdxlst,kmax*kls,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(dqtdylst,kmax*kls,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(dqtdtlst,kmax*kls,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(thlpcart,kmax*kls,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(thlproft,kmax*kls,MY_REAL,0,comm3d,mpierr)
    call MPI_BCAST(qtproft ,kmax*kls,MY_REAL,0,comm3d,mpierr)

    call MPI_BCAST(ltimedepsurf ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(ltimedepz    ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call inittimedepsv
    call timedep

    deallocate(height)


  end subroutine inittimedep

  subroutine timedep

!-----------------------------------------------------------------|
!                                                                 |
!*** *timedep*  calculates ls forcings and surface forcings       |
!               case as a funtion of timee                        |
!                                                                 |
!      Roel Neggers    K.N.M.I.     01/05/2001                    |
!                                                                 |
!                                                                 |
!    calls                                                        |
!    * timedepz                                                   |
!      calculation of large scale advection, radiation and        |
!      surface fluxes by interpolation between prescribed         |
!      values at certain times                                    |
!                                                                 |
!    * timedepsurf                                                |
!      calculation  surface fluxes by interpolation               |
!      between prescribed values at certain times                 |
!                                                                 |
!                                                                 |
!-----------------------------------------------------------------|
    use modtimedepsv, only : timedepsv
    implicit none

    if (.not. ltimedep) return
    call timedepz
    call timedepsurf
    call timedepsv
  end subroutine timedep

  subroutine timedepz
    use modfields,   only : ug, vg, dqtdtls,dqtdxls,dqtdyls, wfls,thlprof,qtprof,thlpcar
    use modglobal,   only : timee
    implicit none

    integer t
    real fac

    if(.not.(ltimedepz)) return

    !---- interpolate ----
    t=1
    do while(timee>timels(t))
      t=t+1
    end do
    if (timee/=timels(1)) then
      t=t-1
    end if

    fac = ( timee-timels(t) ) / ( timels(t+1)-timels(t) )
    ug      = ugt     (:,t) + fac * ( ugt     (:,t+1) - ugt     (:,t) )
    vg      = vgt     (:,t) + fac * ( vgt     (:,t+1) - vgt     (:,t) )
    wfls    = wflst   (:,t) + fac * ( wflst   (:,t+1) - wflst   (:,t) )
    dqtdxls = dqtdxlst(:,t) + fac * ( dqtdxlst(:,t+1) - dqtdxlst(:,t) )
    dqtdyls = dqtdylst(:,t) + fac * ( dqtdylst(:,t+1) - dqtdylst(:,t) )
    dqtdtls = dqtdtlst(:,t) + fac * ( dqtdtlst(:,t+1) - dqtdtlst(:,t) )
    thlpcar = thlpcart(:,t) + fac * ( thlpcart(:,t+1) - thlpcart(:,t) )


    return
  end subroutine timedepz

  subroutine timedepsurf
    use modglobal,   only : timee, lmoist
    use modsurfdata, only : wtsurf,wqsurf,thls,qts,ps
    use modsurf,     only : qtsurf
    implicit none
    integer t
    real fac


    if(.not.(ltimedepsurf)) return
  !     --- interpolate! ----
    t=1
    do while(timee>timeflux(t))
      t=t+1
    end do
    if (timee/=timeflux(t)) then
      t=t-1
    end if

    fac = ( timee-timeflux(t) ) / ( timeflux(t+1)-timeflux(t))
    wqsurf = wqsurft(t) + fac * ( wqsurft(t+1) - wqsurft(t)  )
    wtsurf = wtsurft(t) + fac * ( wtsurft(t+1) - wtsurft(t)  )
    thls   = thlst(t)   + fac * ( thlst(t+1)   - thlst(t)    )
    ps     = pst(t)     + fac * ( pst(t+1)   - pst(t)    )
!cstep: not necessary to provide qts in ls_flux file qts    = qtst(t)    + fac * ( qtst(t+1)    - qtst(t)     )
    if (lmoist) then
       call qtsurf
    else
       qts = 0.
    endif

    return
  end subroutine timedepsurf


  subroutine exittimedep
    use modtimedepsv, only : exittimedepsv
    implicit none
    if (.not. ltimedep) return
    deallocate(timels,ugt,vgt,wflst,dqtdxlst,dqtdylst,dqtdtlst,thlpcart)
    deallocate(timeflux, wtsurft,wqsurft,thlst,qtst,pst)
    call exittimedepsv

  end subroutine

end module modtimedep
