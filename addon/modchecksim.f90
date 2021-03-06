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
module modchecksim

    !-----------------------------------------------------------------|
    !                                                                 |
    !*** *checksim*  Calculates divergence and Courant number         |
    !      modifications Thijs Heus TUDelft 03/08/2007                |
    !                                                                 |
    !____________________SETTINGS_AND_SWITCHES________________________|
    !                      IN &NAMCHECKSIM                            |
    !                                                                 |
    !    tcheck         CHECK INTERVAL                                |
    !-----------------------------------------------------------------|

  implicit none
  private
  public initchecksim,checksim

  real    :: tcheck = 0.,tnext = 3600.
  real    :: dtmn =0.,ndt =0.

  save
contains
  subroutine initchecksim
    use modglobal, only : ifnamopt, fname_options,dtmax,ladaptive,btime
    use modmpi,    only : myid,my_real,comm3d,mpierr
    implicit none
    integer :: ierr
    namelist/NAMCHECKSIM/ &
    tcheck

    if(myid==0)then
      open(ifnamopt,file=fname_options,status='old',iostat=ierr)
      read (ifnamopt,NAMCHECKSIM,iostat=ierr)
      write(6 ,NAMCHECKSIM)
      close(ifnamopt)

      if (.not. ladaptive .and. tcheck < dtmax) then
        tcheck = dtmax
      end if
    end if

    call MPI_BCAST(tcheck     ,1,MY_REAL   ,0,comm3d,mpierr)
    tnext = tcheck-1e-3+btime


  end subroutine initchecksim
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  subroutine checksim
    use modglobal, only : timee, rk3step, dt_lim,dt
    use modmpi,    only : myid
    implicit none
    character(20) :: timeday
    if (timee ==0) return
    if (rk3step/=3) return
    dtmn = dtmn +dt; ndt =ndt+1.
    if(timee<tnext) return
    tnext = tnext+tcheck
    if (myid==0) then
      call date_and_time(time=timeday)
      write (*,*) '================================================================='
      write (*,'(3A,F9.2,A,F6.3)') 'Time of Day: ', timeday(1:10),'    Time of Simulation: ', timee, '    dt: ',dtmn/ndt
    end if
    call calccourant
    call calcpeclet
    call chkdiv
    dtmn  = 0.
    ndt   = 0.

  end subroutine checksim
  subroutine calccourant
!-----------------------------------------------------------------|
!                                                                 |
!      Thijs Heus   TU Delft  13/7/2005                           |
!                                                                 |
!     purpose.                                                    |
!     --------                                                    |
!                                                                 |
!      Calculates the courant number as in max(w) *deltat/deltaz  |
!      and writes it to screen.                                   |
!                                                                 |
!     interface.                                                  |
!     ----------                                                  |
!                                                                 |
!     *calccourant* is called from *program*.                     |
!                                                                 |
!-----------------------------------------------------------------|

    use modglobal, only : i1,j1,kmax,k1,dx,dy,dzh,dt,timee
    use modfields, only : u0,v0,w0
    use modmpi,    only : myid,comm3d,mpierr,mpi_max,my_real
    implicit none


    real          :: courxl,courx,couryl,coury
    real, allocatable, dimension (:) :: courzl,courz,courtotl,courtot
    integer       :: k

    allocate(courzl(k1),courz(k1),courtotl(k1),courtot(k1))
    courzl = 0.0
    courz  = 0.0
    courtotl = 0.0
    courtot  = 0.0
    do k=1,kmax
      courzl(k)=maxval(abs(w0(2:i1,2:j1,k)))*dtmn/dzh(k)
      courtotl(k)=maxval(abs(u0(2:i1,2:j1,k)/dx)+abs(v0(2:i1,2:j1,k)/dy)+abs(w0(2:i1,2:j1,k)/dzh(k)))*dtmn
    end do
    courxl = maxval(abs(u0))*dtmn/dx
    couryl = maxval(abs(v0))*dtmn/dy

    call MPI_ALLREDUCE(courxl,courx,1,MY_REAL,MPI_MAX,comm3d,mpierr)
    call MPI_ALLREDUCE(couryl,coury,1,MY_REAL,MPI_MAX,comm3d,mpierr)
    call MPI_ALLREDUCE(courzl,courz,k1,MY_REAL,MPI_MAX,comm3d,mpierr)
    call MPI_ALLREDUCE(courtotl,courtot,k1,MY_REAL,MPI_MAX,comm3d,mpierr)
    if (myid==0) then
      write(*,'(A,3ES10.2,I5,ES10.2,I5)') 'Courant numbers (x,y,z,tot):',courx,coury,maxval(courz(1:kmax)),maxloc(courz(1:kmax)),maxval(courtot(1:kmax)),maxloc(courtot(1:kmax))
    end if

    deallocate(courzl,courz,courtotl,courtot)

    return
  end subroutine calccourant
  subroutine calcpeclet
!-----------------------------------------------------------------|
!                                                                 |
!      Thijs Heus   KNMI    16/12/2008                            |
!                                                                 |
!     purpose.                                                    |
!     --------                                                    |
!                                                                 |
!      Calculates the cell peclet number as in                    |
!       max(ekm) *deltat/deltax**2                                |
!      and writes it to screen.                                   |
!                                                                 |
!     interface.                                                  |
!     ----------                                                  |
!                                                                 |
!     *calcpeclet* is called from *program*.                      |
!                                                                 |
!-----------------------------------------------------------------|

    use modglobal, only : i1,j1,k1,kmax,dx,dy,dzh,dt,timee
    use modsubgrid,only : ekm
    use modmpi,    only : myid,comm3d,mpierr,mpi_max,my_real
    implicit none


    real, allocatable, dimension (:) :: peclettotl,peclettot
    integer       :: k

    allocate(peclettotl(k1),peclettot(k1))
    peclettotl = 0.
    peclettot  = 0.
    do k=1,kmax
      peclettotl(k)=maxval(ekm(2:i1,2:j1,k))*dtmn/minval((/dzh(k),dx,dy/))**2
    end do

    call MPI_ALLREDUCE(peclettotl,peclettot,k1,MY_REAL,MPI_MAX,comm3d,mpierr)
    if (myid==0) then
      write(6,'(A,ES10.2,I5)') 'Cell Peclet number:',maxval(peclettot(1:kmax)),maxloc(peclettot(1:kmax))
    end if

    deallocate(peclettotl,peclettot)

    return
  end subroutine calcpeclet

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine chkdiv

!-----------------------------------------------------------------|
!                                                                 |
!*** *chkdiv checks local and total divergence                    |
!             for next timestep.                                  |
!                                                                 |
!      Hans Cuijpers   I.M.A.U.    06/01/1995                     |
!      adapted tstep   to chkdiv Mathieu nov 2000
!                                                                 |
!     purpose.                                                    |
!     --------                                                    |
!                                                                 |
!**   interface.                                                  |
!     ----------                                                  |
!                                                                 |
!                                                                 |
!-----------------------------------------------------------------|

    use modglobal, only : i1,j1,kmax,dx,dy,dzf
    use modfields, only : um,vm,wm
    use modmpi,    only : myid,comm3d,mpi_sum,mpi_max,my_real,mpierr
    implicit none



    real div, divmax, divtot
    real divmaxl, divtotl
    integer i, j, k

    divmax = 0.
    divtot = 0.
    divmaxl= 0.
    divtotl= 0.

    do k=1,kmax
    do j=2,j1
    do i=2,i1
      div = &
                (um(i+1,j,k) - um(i,j,k) )/dx + &
                (vm(i,j+1,k) - vm(i,j,k) )/dy + &
                (wm(i,j,k+1) - wm(i,j,k) )/dzf(k)
      divmaxl = max(divmaxl,abs(div))
      divtotl = divtotl + div*dx*dy*dzf(k)
    end do
    end do
    end do

    call MPI_ALLREDUCE(divtotl, divtot, 1,    MY_REAL, &
                          MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(divmaxl, divmax, 1,    MY_REAL, &
                          MPI_MAX, comm3d,mpierr)

    if(myid==0)then
      write(6,'(A,2ES11.2)')'divmax, divtot = ', divmax, divtot
    end if

    return
  end subroutine chkdiv

end module modchecksim

