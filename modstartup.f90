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
module modstartup

! Chiel van Heerwaarden & Thijs Heus  19-07-2007
! Reads initial profiles, and initializes fields
! Reads and writes restart files

implicit none
! private
! public :: startup, writerestartfiles,trestart
save

  logical :: llsadv   = .false. ! switch for large scale forcings

  integer (KIND=selected_int_kind(6)) :: irandom= 0     !    * number to seed the randomnizer with
  integer :: krand = huge(0)
  real :: randthl= 0.1,randqt=1e-5                 !    * thl and qt amplitude of randomnization
  
contains
  subroutine startup

      !-----------------------------------------------------------------|
      !                                                                 |
      !     Reads all general options from namoptions                   |
      !                                                                 |
      !      Chiel van Heerwaarden        15/06/2007                    |
      !      Thijs Heus                   15/06/2007                    |
      !-----------------------------------------------------------------|

    use modglobal,         only : initglobal,iexpnr,runtime, dtmax,dtav_glob,timeav_glob,&
                                  lwarmstart,startfile,trestart,&
                                  nsv,imax,jtot,kmax,xsize,ysize,xlat,xlon,xday,xtime,&
                                  lmoist,lcoriol,cu, cv,ifnamopt,fname_options,&
                                  iadv_mom,iadv_tke,iadv_thl,iadv_qt,iadv_sv,courant,peclet,ladaptive
    use modsurfdata,       only : z0,ustin,wtsurf,wqsurf,wsvsurf,ps,thls,isurf,lneutraldrag
    use modsurf,           only : initsurf
    use modfields,         only : initfields
    use modpois,           only : initpois
    use modradiation,      only : initradiation,irad,iradiation,&
                                  rad_ls,rad_longw,rad_shortw,rad_smoke,&
                                  timerad,rka,dlwtop,dlwbot,sw0,gc,sfc_albedo,reff,isvsmoke
!     use modradiation,      only : initradiation,irad,&
!                                   rad_ls,rad_longw,rad_shortw,rad_smoke,&
!                                   timerad!,rka,dlwtop,dlwbot,sw0,gc,sfc_albedo,reff,isvsmoke
    use modtimedep,        only : inittimedep,ltimedep
    use modboundary,       only : initboundary,ksp
    use modthermodynamics, only : initthermodynamics,lqlnr    !cstep remove chi_half
    use modmicrophysics,   only : initmicrophysics
    use modsubgrid,        only : initsubgrid,ldelta, cf,cn,Rigc,Prandtl,lmason
    use modmpi,            only : comm3d,myid, mpi_integer,mpi_logical,my_real,mpierr, mpi_character

    implicit none
    integer :: ierr

  !declare namelists


    namelist/RUN/ &
        iexpnr,lwarmstart,startfile, runtime, dtmax,dtav_glob,timeav_glob,&
        trestart,irandom,randthl,randqt,krand,nsv,courant,peclet,ladaptive
    namelist/DOMAIN/ &
        imax,jtot,kmax,&
        xsize,ysize,&
        xlat,xlon,xday,xtime,ksp
    namelist/PHYSICS/ &
        !cstep z0,ustin,wtsurf,wqsurf,wsvsurf,ps,thls,chi_half,lmoist,isurf,lneutraldrag,&
         z0,ustin,wtsurf,wqsurf,wsvsurf,ps,thls,lmoist,isurf,lneutraldrag,&
        lcoriol,ltimedep,irad,timerad,iradiation,rad_ls,rad_longw,rad_shortw,rad_smoke,&
        rka,dlwtop,dlwbot,sw0,gc,sfc_albedo,reff,isvsmoke
    namelist/DYNAMICS/ &
        llsadv, lqlnr, cu, cv, iadv_mom, iadv_tke, iadv_thl, iadv_qt, iadv_sv
    namelist/SUBGRID/ &
        ldelta,lmason, cf,cn,Rigc,Prandtl
!   logical :: ldelta   = .false. ! switch for subgrid
  !read namelists

    if(myid==0)then
      if (command_argument_count() >=1) then
        call get_command_argument(1,fname_options)
      end if
      write (*,*) fname_options

      open(ifnamopt,file=fname_options,status='old',iostat=ierr)
      if (ierr /= 0) then
        stop 'ERROR:Namoptions does not exist'
      end if
      read (ifnamopt,RUN)
      write(6 ,RUN)
      read (ifnamopt,DOMAIN)
      write(6 ,DOMAIN)
      read (ifnamopt,PHYSICS)
      write(6 ,PHYSICS)
      read (ifnamopt,DYNAMICS,iostat=ierr)
      write(6 ,DYNAMICS)
      read (ifnamopt,SUBGRID,iostat=ierr)
      write(6 ,SUBGRID)
      close(ifnamopt)
    end if


  !broadcast namelists
    call MPI_BCAST(iexpnr     ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(lwarmstart ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(startfile  ,50,MPI_CHARACTER,0,comm3d,mpierr)
    call MPI_BCAST(runtime    ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(trestart   ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(dtmax      ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(dtav_glob  ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(timeav_glob,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(nsv        ,1,MPI_INTEGER,0,comm3d,mpierr)

    call MPI_BCAST(imax       ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(jtot       ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(kmax       ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(xsize      ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(ysize      ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(xlat       ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(xlon       ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(xday       ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(xtime      ,1,MY_REAL   ,0,comm3d,mpierr)

    call MPI_BCAST(z0         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(ustin      ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(lneutraldrag ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(wtsurf     ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(wqsurf     ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(wsvsurf(1:nsv),nsv,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(ps         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(thls       ,1,MY_REAL   ,0,comm3d,mpierr)
    !cstep   call MPI_BCAST(chi_half   ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(lmoist     ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(lcoriol    ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(ltimedep   ,1,MPI_LOGICAL,0,comm3d,mpierr)

    call MPI_BCAST(irad       ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(timerad    ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(iradiation ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(rad_ls     ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(rad_longw  ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(rad_shortw ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(rad_smoke  ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(rka        ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(dlwtop     ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(dlwbot     ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(sw0        ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(gc         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(sfc_albedo ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(reff       ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(isvsmoke   ,1,MPI_INTEGER,0,comm3d,mpierr)
        
    call MPI_BCAST(llsadv     ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(lqlnr      ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(cu         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(cv         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(ksp        ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(irandom    ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(krand      ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(randthl    ,1,MY_REAL    ,0,comm3d,mpierr)
    call MPI_BCAST(randqt     ,1,MY_REAL   ,0,comm3d,mpierr)
    
    call MPI_BCAST(ladaptive  ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(courant,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(peclet,1,MY_REAL   ,0,comm3d,mpierr)

    call MPI_BCAST(isurf   ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(iadv_mom,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(iadv_tke,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(iadv_thl,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(iadv_qt ,1,MPI_INTEGER,0,comm3d,mpierr)
    call MPI_BCAST(iadv_sv(1:nsv) ,nsv,MPI_INTEGER,0,comm3d,mpierr)

    call MPI_BCAST(ldelta     ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(lmason     ,1,MPI_LOGICAL,0,comm3d,mpierr)
    call MPI_BCAST(cf         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(cn         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(Rigc       ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(Prandtl    ,1,MY_REAL   ,0,comm3d,mpierr)

  ! Allocate and initialize core modules
    call initglobal
    call initfields

    call initboundary
    call initthermodynamics
    call initsurf
    call initsubgrid
    !call initradiation
    call initpois
    call initmicrophysics
    call inittimedep !depends on modglobal,modfields, modmpi, modsurf, modradiation

    call checkinitvalues
    call readinitfiles
    call initradiation

  end subroutine startup


  subroutine checkinitvalues
  !-----------------------------------------------------------------|
  !                                                                 |
  !      Thijs Heus   TU Delft  9/2/2006                            |
  !                                                                 |
  !     purpose.                                                    |
  !     --------                                                    |
  !                                                                 |
  !      checks whether crucial parameters are set correctly        |
  !                                                                 |
  !     interface.                                                  |
  !     ----------                                                  |
  !                                                                 |
  !     *checkinitvalues* is called from *program*.                 |
  !                                                                 |
  !-----------------------------------------------------------------|

    use modsurfdata,only : wtsurf,wqsurf, ustin,thls,z0,isurf,ps
    use modglobal, only : imax,jtot, ysize,xsize,dtmax,runtime, startfile,lwarmstart
    use modmpi,    only : myid, nprocs,mpierr


      if(mod(jtot,nprocs) /= 0) then
        if(myid==0)then
          write(6,*)'STOP ERROR IN NUMBER OF PROCESSORS'
          write(6,*)'nprocs must divide jtot!!! '
          write(6,*)'nprocs and jtot are: ',nprocs, jtot
        end if
        call MPI_FINALIZE(mpierr)
        stop
      end if

      if(mod(imax,nprocs)/=0)then
        if(myid==0)then
          write(6,*)'STOP ERROR IN NUMBER OF PROCESSORS'
          write(6,*)'nprocs must divide imax!!! '
          write(6,*)'nprocs and imax are: ',nprocs,imax
        end if
        call MPI_FINALIZE(mpierr)
        stop
      end if

  !Check Namroptions


    if (runtime < 0)stop 'runtime out of range/not set'
    if (dtmax < 0)  stop 'dtmax out of range/not set '
    if (ps < 0)     stop 'psout of range/not set'
    if (thls < 0)   stop 'thls out of range/not set'
    if (xsize < 0)  stop 'xsize out of range/not set'
    if (ysize < 0)  stop 'ysize out of range/not set '

    if (lwarmstart) then
      if (startfile == '') stop 'no restartfile set'
    end if
  !isurf
    select case (isurf)
    case(1)
    case(2,10)
      if (z0<0) stop 'z0 out of range/not set'
    case(3:4)
      if (wtsurf<0)  stop 'wtsurf out of range/not set'
      if (wqsurf<0)  stop 'wtsurf out of range/not set'
    case default
      stop 'isurf out of range/not set'
    end select
    if (isurf ==3) then
      if (ustin < 0)  stop 'ustin out of range/not set'
    end if


  end subroutine checkinitvalues

  subroutine readinitfiles
    use modfields,         only : u0,v0,w0,um,vm,wm,thlm,thl0,thl0h,qtm,qt0,qt0h,&
                                  ql0,ql0h,thv0h,sv0,svm,e12m,e120,&
                                  dudxls,dudyls,dvdxls,dvdyls,dthldxls,dthldyls,&
                                  dqtdxls,dqtdyls,dqtdtls,dpdxl,dpdyl,&
                                  wfls,whls,ug,vg,uprof,vprof,thlprof, qtprof,e12prof, svprof,&
                                  v0av,u0av,qt0av,ql0av,thl0av,sv0av,exnf,exnh,presf,presh,rhof,&
                                  thlpcar
    use modglobal,         only : i1,i2,ih,j1,j2,jh,kmax,k1,dtmax,dt,timee,ntimee,ntrun,btime,nsv,&
                                  zf,dzf,dzh,rv,rd,grav,cp,rlv,pref0,om23,&
                                  rslabs,cu,cv,e12min,dzh,dtheta,dqt,dsv,cexpnr,ifinput,lwarmstart,trestart
    use modsubgrid,        only : ekm,ekh
    use modsurfdata,       only : wtsurf,wqsurf,wsvsurf,&
                                  thls,thvs,ustin,ps,qts,isurf,svs
    use modsurf,           only : surf,qtsurf,surflux,calust
    use modboundary,       only : boundary,tqaver
    use modmpi,            only : slabsum,myid,comm3d,mpierr,my_real
    use modthermodynamics, only : thermodynamics,calc_halflev

    integer i,j,k,n

    real, allocatable :: height(:), th0av(:)
    real tv


    character(80) chmess

    allocate (height(k1))
    allocate (th0av(k1))



    if (.not. lwarmstart) then


    !********************************************************************

    !    1.0 prepare initial fields from files 'prog.inp' and 'scalar.inp'
    !    ----------------------------------------------------------------

    !--------------------------------------------------------------------
    !    1.1 read fields
    !-----------------------------------------------------------------

      dt = dtmax / 100.
      timee = 0.0
      if (myid==0) then
        open (ifinput,file='prof.inp.'//cexpnr)
        read (ifinput,'(a80)') chmess
        write(*,     '(a80)') chmess
        read (ifinput,'(a80)') chmess

        do k=1,kmax
          read (ifinput,*) &
                height (k), &
                thlprof(k), &
                qtprof (k), &
                uprof  (k), &
                vprof  (k), &
                e12prof(k)
        end do

        close(ifinput)
        write(*,*) 'height    thl      qt         u      v     e12'
        do k=kmax,1,-1
          write (*,'(f7.1,f8.1,e12.4,3f7.1)') &
                height (k), &
                thlprof(k), &
                qtprof (k), &
                uprof  (k), &
                vprof  (k), &
                e12prof(k)

        end do

        if (minval(e12prof(1:kmax)) < e12min) then
          write(*,*)  'e12 value is zero (or less) in prof.inp'
          do k=1,kmax
            e12prof(k) = max(e12prof(k),e12min)
          end do
        end if

      end if ! end if myid==0
    ! MPI broadcast numbers reading
      call MPI_BCAST(thlprof,kmax,MY_REAL   ,0,comm3d,mpierr)
      call MPI_BCAST(qtprof ,kmax,MY_REAL   ,0,comm3d,mpierr)
      call MPI_BCAST(uprof  ,kmax,MY_REAL   ,0,comm3d,mpierr)
      call MPI_BCAST(vprof  ,kmax,MY_REAL   ,0,comm3d,mpierr)
      call MPI_BCAST(e12prof,kmax,MY_REAL   ,0,comm3d,mpierr)
      do k=1,kmax
      do j=1,j2
      do i=1,i2
        thl0(i,j,k) = thlprof(k)
        thlm(i,j,k) = thlprof(k)
        qt0 (i,j,k) = qtprof (k)
        qtm (i,j,k) = qtprof (k)
        u0  (i,j,k) = uprof  (k) - cu
        um  (i,j,k) = uprof  (k) - cu
        v0  (i,j,k) = vprof  (k) - cv
        vm  (i,j,k) = vprof  (k) - cv
        w0  (i,j,k) = 0.0
        wm  (i,j,k) = 0.0
        e120(i,j,k) = e12prof(k)
        e12m(i,j,k) = e12prof(k)
        ekm (i,j,k) = 0.0
        ekh (i,j,k) = 0.0
      end do
      end do
      end do
    !---------------------------------------------------------------
    !  1.2 randomnize fields
    !---------------------------------------------------------------

      krand  = min(krand,kmax)
      do k = 1,krand
        call randomnize(qtm ,k,randqt ,irandom,ih,jh)
        call randomnize(qt0 ,k,randqt ,irandom,ih,jh)
        call randomnize(thlm,k,randthl,irandom,ih,jh)
        call randomnize(thl0,k,randthl,irandom,ih,jh)
      end do

      svprof = 0.
      if(myid==0)then
        if (nsv>0) then
          open (ifinput,file='scalar.inp.'//cexpnr)
          read (ifinput,'(a80)') chmess
          read (ifinput,'(a80)') chmess
          do k=1,kmax
            read (ifinput,*) &
                  height (k), &
                  (svprof (k,n),n=1,nsv)
          end do
          open (ifinput,file='scalar.inp.'//cexpnr)
          write (6,*) 'height   sv(1) --------- sv(nsv) '
          do k=kmax,1,-1
            write (6,*) &
                  height (k), &
                (svprof (k,n),n=1,nsv)
          end do

        end if
      end if ! end if myid==0

      call MPI_BCAST(wsvsurf,nsv   ,MY_REAL   ,0,comm3d,mpierr)

      call MPI_BCAST(svprof ,k1*nsv,MY_REAL   ,0,comm3d,mpierr)
      do k=1,kmax
        do j=1,j2
          do i=1,i2
            do n=1,nsv
              sv0(i,j,k,n) = svprof(k,n)
              svm(i,j,k,n) = svprof(k,n)
            end do
          end do
        end do
      end do

!-----------------------------------------------------------------
!    2.2 Initialize surface layer
!-----------------------------------------------------------------

      !CvH
      !thls = thlprof(1)

      select case(isurf)
      case(1,2,10)
        call qtsurf
      case(3,4)
        thls = thlprof(1)
        qts  = qtprof(1)
      end select
      thvs = thls*(1+(rv/rd-1)*qts)
      u0av(1)   = uprof(1)
      thl0av(1) = thlprof(1)
      svs = svprof(1,:)
      call surf

      dtheta = (thlprof(kmax)-thlprof(kmax-1)) / dzh(kmax)
      dqt    = (qtprof (kmax)-qtprof (kmax-1)) / dzh(kmax)
      do n=1,nsv
        dsv(n) = (svprof(kmax,n)-svprof(kmax-1,n)) / dzh(kmax)
      end do

      call boundary
      call thermodynamics


    else !if lwarmstart


      call readrestartfiles
      um   = u0
      vm   = v0
      wm   = w0
      thlm = thl0
      qtm  = qt0
      svm  = sv0
      e12m = e120
      call calc_halflev
      exnf = (presf/pref0)**(rd/cp)
      exnh = (presh/pref0)**(rd/cp)

      do  j=2,j1
      do  i=2,i1
      do  k=2,k1
        thv0h(i,j,k) = (thl0h(i,j,k)+rlv*ql0h(i,j,k)/(cp*exnh(k))) &
                      *(1+(rv/rd-1)*qt0h(i,j,k)-rv/rd*ql0h(i,j,k))
      end do
      end do
      end do

      u0av = 0.0
      v0av = 0.0
      thl0av = 0.0
      th0av  = 0.0
      qt0av  = 0.0
      ql0av  = 0.0
      sv0av = 0.

      !CvH changed momentum array dimensions to same value as scalars!
      call slabsum(u0av  ,1,k1,u0  ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
      call slabsum(v0av  ,1,k1,v0  ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
      call slabsum(thl0av,1,k1,thl0,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
      call slabsum(qt0av ,1,k1,qt0 ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)
      call slabsum(ql0av ,1,k1,ql0 ,2-ih,i1+ih,2-jh,j1+jh,1,k1,2,i1,2,j1,1,k1)

      u0av  = u0av  /rslabs + cu
      v0av  = v0av  /rslabs + cv
      thl0av = thl0av/rslabs
      qt0av = qt0av /rslabs
      ql0av = ql0av /rslabs
      th0av  = thl0av + (rlv/cp)*ql0av/exnf
      do k=1,k1
        tv      = th0av(k)*exnf(k)*(1.+(rv/rd-1)*qt0av(k)-rv/rd*ql0av(k))
        rhof(k) = presf(k)/(rd*tv)
      end do
      dt=dtmax

    end if

!-----------------------------------------------------------------
!    2.1 read and initialise fields
!-----------------------------------------------------------------


    if(myid==0)then
      open (ifinput,file='lscale.inp.'//cexpnr)
      read (ifinput,'(a80)') chmess
      read (ifinput,'(a80)') chmess
      write(6,*) ' height u_geo   v_geo    subs     ' &
                    ,'   dqtdx      dqtdy        dqtdtls     thl_rad '
      do  k=1,kmax
        read (ifinput,*) &
              height (k), &
              ug     (k), &
              vg     (k), &
              wfls   (k), &
              dqtdxls(k), &
              dqtdyls(k), &
              dqtdtls(k), &
              thlpcar(k)
      end do
      close(ifinput)

      do k=kmax,1,-1
        write (6,'(3f7.1,5e12.4)') &
              height (k), &
              ug     (k), &
              vg     (k), &
              wfls   (k), &
              dqtdxls(k), &
              dqtdyls(k), &
              dqtdtls(k), &
              thlpcar(k)
      end do


    end if ! end myid==0

! MPI broadcast variables read in


    call MPI_BCAST(ug       ,kmax,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(vg       ,kmax,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(wfls     ,kmax,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(dqtdxls  ,kmax,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(dqtdyls  ,kmax,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(dqtdtls  ,kmax,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(thlpcar  ,kmax,MY_REAL   ,0,comm3d,mpierr)

!-----------------------------------------------------------------
!    2.3 make large-scale horizontal pressure gradient
!-----------------------------------------------------------------

!******include rho if rho = rho(z) /= 1.0 ***********

    do k=1,kmax
      dpdxl(k) =  om23*vg(k)
      dpdyl(k) = -om23*ug(k)
    end do

  !-----------------------------------------------------------------
  !    2.5 make large-scale horizontal gradients
  !-----------------------------------------------------------------

    whls(1)  = 0.0
    do k=2,kmax
      whls(k) = ( wfls(k)*dzf(k-1) +  wfls(k-1)*dzf(k) )/(2*dzh(k))
    end do
    whls(k1) = (wfls(kmax)+0.5*dzf(kmax)*(wfls(kmax)-wfls(kmax-1)) &
                                                  /dzh(kmax))

  !******include rho if rho = rho(z) /= 1.0 ***********

    if (llsadv) then

      dudxls  (1) = -0.5 *( whls(2)-whls(1) )/ dzf(k)
      dudyls  (1) =  0.0
      dvdxls  (1) = -0.5 *( whls(2)-whls(1) )/ dzf(k)
      dvdyls  (1) =  0.0
      dthldxls(1) = om23*thlprof(1)/grav &
                        * (vg(2)-vg(1))/dzh(2)
      dthldyls(1) = -om23*thlprof(1)/grav &
                        * (ug(2)-ug(1))/dzh(2)

      do k=2,kmax-1
        dudxls(k) = -0.5 *( whls(k+1)-whls(k) )/ dzf(k)
        dudyls(k) =  0.0
        dvdxls(k) = -0.5 *( whls(k+1)-whls(k) )/ dzf(k)
        dvdyls(k) =  0.0
        dthldxls(k) = om23*thlprof(k)/grav &
                        * (vg(k+1)-vg(k-1))/(zf(k+1)-zf(k-1))
        dthldyls(k) = -om23*thlprof(k)/grav &
                        * (ug(k+1)-ug(k-1))/(zf(k+1)-zf(k-1))
      end do

      dudxls  (kmax) = -0.5 *( whls(k1)-whls(kmax) )/ dzf(k)
      dudyls  (kmax) =  0.0
      dvdxls  (kmax) = -0.5 *( whls(k1)-whls(kmax) )/ dzf(k)
      dvdyls  (kmax) =  0.0
      dthldxls(kmax) =  0.0
      dthldyls(kmax) =  0.0

    else

      dudxls   = 0.0
      dudyls   = 0.0
      dvdxls   = 0.0
      dvdyls   = 0.0
      dthldxls = 0.0
      dthldyls = 0.0

    end if


    btime   = timee
    ntrun   = 0
    ntimee  = nint(timee/dtmax)
    deallocate (height,th0av)


  end subroutine readinitfiles

  subroutine readrestartfiles

    use modsurfdata,only : ustar,tstar,qstar,svstar,dudz,dvdz,dthldz,dqtdz,ps,thls,qts,thvs
    use modfields, only : u0,v0,w0,thl0,qt0,ql0,ql0h,e120,dthvdz,presf,presh,sv0
    use modglobal, only : i1,i2,ih,j1,j2,jh,k1,dtheta,dqt,dsv,startfile,timee,&
                          iexpnr,ntimee,rk3step,ifinput,nsv,runtime
    use modmpi,    only : cmyid


    character(50) :: name
    integer i,j,k,n
    !********************************************************************

  !    1.0 Read initfiles
  !-----------------------------------------------------------------
    name = startfile
    name(5:5) = 'd'
    name(12:14)=cmyid
    write(6,*) 'loading ',name
    open(unit=ifinput,file=name,form='unformatted', status='old')

      read(ifinput)  (((u0    (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)  (((v0    (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)  (((w0    (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)  (((thl0  (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)  (((qt0   (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)  (((ql0   (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)  (((ql0h  (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)  (((e120  (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)  (((dthvdz(i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      read(ifinput)   ((ustar (i,j  ),i=1,i2      ),j=1,j2      )
      read(ifinput)   ((tstar (i,j  ),i=1,i2      ),j=1,j2      )
      read(ifinput)   ((qstar (i,j  ),i=1,i2      ),j=1,j2      )
      read(ifinput)   ((dthldz(i,j  ),i=1,i2      ),j=1,j2      )
      read(ifinput)   ((dqtdz (i,j  ),i=1,i2      ),j=1,j2      )
      read(ifinput)  (  presf (    k)                            ,k=1,k1)
      read(ifinput)  (  presh (    k)                            ,k=1,k1)
      read(ifinput)  ps,thls,qts,thvs
      read(ifinput)  dtheta,dqt,timee

    close(ifinput)

    if (nsv>0) then
      name(5:5) = 's'
      write(6,*) 'loading ',name
      open(unit=ifinput,file=name,form='unformatted')
      read(ifinput) ((((sv0(i,j,k,n),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1),n=1,nsv)
      read(ifinput) (((svstar(i,j,n),i=1,i2),j=1,j2),n=1,nsv)
      read(ifinput) (dsv(n),n=1,nsv)
      read(ifinput)  timee
      close(ifinput)
    end if


  end subroutine readrestartfiles
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  subroutine writerestartfiles
    use modsurfdata,only : ustar,tstar,qstar,svstar,dudz,dvdz,dthldz,dqtdz,ps,thls,qts,thvs
    use modfields, only : u0,v0,w0,thl0,qt0,ql0,ql0h,e120,dthvdz,presf,presh,sv0
    use modglobal, only : i1,i2,ih,j1,j2,jh,k1,dsv,trestart,tnextrestart,dt_lim,timee,cexpnr,&
                          ntimee,rk3step,ifoutput,nsv,runtime,dtheta,dqt
    use modmpi,    only : cmyid,myid

    implicit none
    logical :: lexitnow = .false.
    integer imin,ihour
    integer i,j,k,n
    character(20) name

    if (timee == 0) return
    if (rk3step /=3) return
    name = 'exit_now.'//cexpnr
    inquire(file=trim(name), EXIST=lexitnow)
    if (lexitnow .and. myid == 0 ) then
      open(1, file=trim(name), status='old')
      close(1,status='delete')
      write(*,*) 'Stopped at t=',timee
    end if

!     if (mod(ntimee,ntrestart)==0 .or. lexitnow) then
    if (timee<tnextrestart) dt_lim = min(dt_lim,tnextrestart-timee)
    if (timee>=tnextrestart .or. lexitnow) then
      tnextrestart = tnextrestart+trestart
      ihour = floor(timee/3600)
      imin  = floor((timee-ihour * 3600) /3600. * 60.)
      name = 'initd  h  m   .'
      write (name(6:7)  ,'(i2.2)') ihour
      write (name(9:10) ,'(i2.2)') imin
      name(12:14)= cmyid
      name(16:18)= cexpnr
      open  (ifoutput,file=name,form='unformatted',status='replace')

      write(ifoutput)  (((u0    (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)  (((v0    (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)  (((w0    (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)  (((thl0  (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)  (((qt0   (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)  (((ql0   (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)  (((ql0h  (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)  (((e120  (i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)  (((dthvdz(i,j,k),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1)
      write(ifoutput)   ((ustar (i,j  ),i=1,i2      ),j=1,j2      )
      write(ifoutput)   ((tstar (i,j  ),i=1,i2      ),j=1,j2      )
      write(ifoutput)   ((qstar (i,j  ),i=1,i2      ),j=1,j2      )
      write(ifoutput)   ((dthldz(i,j  ),i=1,i2      ),j=1,j2      )
      write(ifoutput)   ((dqtdz (i,j  ),i=1,i2      ),j=1,j2      )
      write(ifoutput)  (  presf (    k)                            ,k=1,k1)
      write(ifoutput)  (  presh (    k)                            ,k=1,k1)
      write(ifoutput)  ps,thls,qts,thvs
      write(ifoutput)  dtheta,dqt,timee

      close (ifoutput)

      if (nsv>0) then
        name  = 'inits  h  m   .'
        write (name(6:7)  ,'(i2.2)') ihour
        write (name(9:10) ,'(i2.2)') imin
        name(12:14) = cmyid
        name(16:18) = cexpnr
        open  (ifoutput,file=name,form='unformatted')
        write(ifoutput) ((((sv0(i,j,k,n),i=2-ih,i1+ih),j=2-jh,j1+jh),k=1,k1),n=1,nsv)
        write(ifoutput) (((svstar(i,j,n),i=1,i2),j=1,j2),n=1,nsv)
        write(ifoutput) (dsv(n),n=1,nsv)
        write(ifoutput)  timee

        close (ifoutput)
      end if
      if (lexitnow) then
        runtime = 0  !jump out of the time loop
      end if

      if (myid==0) then
        write(*,'(A,F15.7,A,I4)') 'dump at time = ',timee,' unit = ',ifoutput
      end if

    end if


  end subroutine writerestartfiles

  subroutine exitmodules
    use modfields,         only : exitfields
    use modglobal,         only : exitglobal
    use modmpi,            only : exitmpi
    use modboundary,       only : exitboundary
    use modmicrophysics,   only : exitmicrophysics
    use modpois,           only : exitpois
    use modtimedep,        only : exittimedep
    use modradiation,      only : exitradiation
    use modsubgrid,        only : exitsubgrid
    use modsurf,           only : exitsurf
    use modthermodynamics, only : exitthermodynamics

    call exittimedep
    call exitthermodynamics
    call exitsurf
    call exitsubgrid
    call exitradiation
    call exitpois
    call exitmicrophysics
    call exitboundary
    call exitfields
    call exitglobal
    call exitmpi

 end subroutine exitmodules
!----------------------------------------------------------------
  subroutine randomnize(field,klev,ampl,ir,ihl,jhl)

    use modmpi,    only :  myid,nprocs
    use modglobal, only : i1,imax,jmax,j1,k1
    integer (KIND=selected_int_kind(6)):: imm, ia, ic,ir
    integer ihl, jhl
    integer i,j,klev
    integer m,mfac
    real ran,ampl
    real field(2-ihl:i1+ihl,2-jhl:j1+jhl,k1)
    parameter (imm = 134456, ia = 8121, ic = 28411)

    if (myid>0) then
      mfac = myid * jmax * imax
      do m =1,mfac
        ir=mod((ir)*ia+ic,imm)

      end do
    end if
    do j=2,j1
    do i=2,i1
      ir=mod((ir)*ia+ic,imm)
      ran=real(ir)/real(imm)
      field(i,j,klev) = field(i,j,klev) + (ran-0.5)*2.0*ampl
    end do
    end do

    if (nprocs-1-myid > 0) then
      mfac = (nprocs-1-myid) * imax * jmax
      do m=1,mfac
        ir=mod((ir)*ia+ic,imm)
      end do
    end if

    return
  end subroutine randomnize


end module modstartup
