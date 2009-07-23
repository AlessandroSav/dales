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
module modradstat

    !-----------------------------------------------------------------|
    !                                                                 |
    !*** *stattend*  calculates slab averaged radiation statistics    |
    !                                                                 |
    !____________________SETTINGS_AND_SWITCHES________________________|
    !                     IN &NAMTIMESTAT                             |
    !                                                                 |
    !    dtav           SAMPLING INTERVAL                             |
    !                                                                 |
    !    timeav         INTERVAL OF WRITING                           |
    !                                                                 |
    !    lstat      SWITCH TO ENABLE TIMESERIES                       |
    !-----------------------------------------------------------------|

implicit none
!private
PUBLIC :: initradstat, radstat, exitradstat
save

  real    :: dtav, timeav,tnext,tnextwrite
  integer :: nsamples
  logical :: lstat= .false. ! switch for conditional sampling cloud (on/off)

!     ------

  real, allocatable :: tllwtendavl(:)
  real, allocatable :: tlswtendavl(:)
  real, allocatable :: lwuavl(:)
  real, allocatable :: lwdavl(:)
  real, allocatable :: swnavl(:)

!   --------------
  real, allocatable :: tllwtendav(:)
  real, allocatable :: tlswtendav(:)
  real, allocatable :: lwuav(:)
  real, allocatable :: lwdav(:)
  real, allocatable :: swnav(:)

!
  real, allocatable :: tllwtendmn(:)
  real, allocatable :: tlswtendmn(:)
  real, allocatable :: lwumn(:)
  real, allocatable :: lwdmn(:)
  real, allocatable :: swnmn(:)
  real, allocatable :: tlradlsmn(:)

contains

  subroutine initradstat
    use modmpi,    only : myid,mpierr, comm3d,my_real, mpi_logical
    use modglobal, only : dtmax, k1, ifnamopt,fname_options, ifoutput, cexpnr,dtav_glob,timeav_glob,ladaptive,dt_lim,btime


    implicit none

    integer ierr
    namelist/NAMRADSTAT/ &
    dtav,timeav,lstat

    dtav=dtav_glob;timeav=timeav_glob
    lstat = .false.

    if(myid==0)then
      open(ifnamopt,file=fname_options,status='old',iostat=ierr)
      read (ifnamopt,NAMRADSTAT,iostat=ierr)
      write(6 ,NAMRADSTAT)
      close(ifnamopt)
    end if

    call MPI_BCAST(timeav     ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(dtav       ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(lstat   ,1,MPI_LOGICAL,0,comm3d,mpierr)

    tnext      = dtav-1e-3+btime
    tnextwrite = timeav-1e-3+btime
    nsamples = nint(timeav/dtav)

   !allocate variables that are needed in modradiation
    allocate(lwdavl(k1))
    allocate(lwuavl(k1))
    allocate(swnavl(k1))
    allocate (tllwtendavl(k1))
    allocate (tlswtendavl(k1))

    if(.not.(lstat)) return
    dt_lim = min(dt_lim,tnext)

    if (abs(timeav/dtav-nsamples)>1e-4) then
      stop 'timeav must be a integer multiple of dtav'
    end if
    if (.not. ladaptive .and. abs(dtav/dtmax-nint(dtav/dtmax))>1e-4) then
      stop 'dtav should be a integer multiple of dtmax'
    end if

    allocate(lwuav(k1))
    allocate(lwdav(k1))
    allocate(swnav(k1))
    allocate(tllwtendav(k1))
    allocate(tlswtendav(k1))

    allocate(lwumn(k1))
    allocate(lwdmn(k1))
    allocate(swnmn(k1))
    allocate(tllwtendmn(k1))
    allocate(tlswtendmn(k1))
    allocate(tlradlsmn(k1))

    lwumn = 0.0
    lwdmn = 0.0
    swnmn = 0.0
    tllwtendmn = 0.0
    tlswtendmn = 0.0
    tlradlsmn  = 0.0

    if(myid==0)then
      open (ifoutput,file='radstat.'//cexpnr,status='replace')
      close (ifoutput)
    end if

  end subroutine initradstat
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  subroutine radstat
    use modglobal, only : rk3step,timee,dt_lim
    implicit none
    if (.not. lstat) return
    if (rk3step/=3) return
    if(timee<tnext .and. timee<tnextwrite) then
      dt_lim = minval((/dt_lim,tnext-timee,tnextwrite-timee/))
      return
    end if
    if (timee>=tnext) then
      tnext = tnext+dtav
      call do_radstat
    end if
    if (timee>=tnextwrite) then
      tnextwrite = tnextwrite+timeav
      call writeradstat
    end if
    dt_lim = minval((/dt_lim,tnext-timee,tnextwrite-timee/))

  end subroutine radstat
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  subroutine do_radstat

    use modmpi,    only : nprocs,comm3d,nprocs,my_real, mpi_sum,mpierr, slabsum
    use modglobal, only : kmax,rslabs,cp,dzf,i1,j1,k1
    use modfields, only : thlpcar
    use modradiation, only : lwd,lwu,swn, rho_air_mn

    implicit none
    integer :: k

    lwdav  = 0.
    lwuav  = 0.
    swnav  = 0.
    tllwtendav = 0.
    tlswtendav = 0.
    lwdavl  = 0.
    lwuavl  = 0.
    swnavl  = 0.
    tllwtendavl = 0.
    tlswtendavl = 0.

    do k=1,k1
      lwdavl(k) = sum(lwd(2:i1,2:j1,k))
      lwuavl(k) = sum(lwu(2:i1,2:j1,k))
      swnavl(k) = sum(swn(2:i1,2:j1,k))
    end do

    do k=1,kmax
      tllwtendavl(k) = -(lwdavl(k+1)-lwdavl(k)+lwuavl(k+1)-lwuavl(k))/(rho_air_mn*cp*dzf(k))
      tlswtendavl(k) =  (swnavl(k+1)-swnavl(k))/(rho_air_mn*cp*dzf(k))
    end do
    !swnavl = swnav

    call MPI_ALLREDUCE(lwdavl, lwdav, kmax,    MY_REAL, &
                         MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(lwuavl, lwuav, kmax,    MY_REAL, &
                         MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(swnavl, swnav, kmax,    MY_REAL, &
                         MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(tllwtendavl, tllwtendav, kmax,    MY_REAL, &
                         MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(tlswtendavl, tlswtendav, kmax,    MY_REAL, &
                         MPI_SUM, comm3d,mpierr)

 !    ADD SLAB AVERAGES TO TIME MEAN

    lwumn = lwumn + lwuav/rslabs
    lwdmn = lwdmn + lwdav/rslabs
    swnmn = swnmn + swnav/rslabs
    tllwtendmn = tllwtendmn + tllwtendav/rslabs
    tlswtendmn = tlswtendmn + tlswtendav/rslabs
    tlradlsmn  = tlradlsmn  + thlpcar

  end subroutine do_radstat

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  subroutine writeradstat
      use modmpi,    only : myid
      use modglobal, only : cexpnr,ifoutput,kmax,zf,timee


      implicit none

      integer nsecs, nhrs, nminut,k


      nsecs   = nint(timee)
      nhrs    = int(nsecs/3600)
      nminut  = int(nsecs/60)-nhrs*60
      nsecs   = mod(nsecs,60)

      lwumn   = lwumn    /nsamples
      lwdmn   = lwdmn    /nsamples
      swnmn   = swnmn    /nsamples
      tllwtendmn = tllwtendmn /nsamples
      tlswtendmn = tlswtendmn /nsamples
      tlradlsmn  = tlradlsmn  /nsamples

  !     ----------------------
  !     2.0  write the fields
  !           ----------------

    if(myid==0)then
      open (ifoutput,file='radstat.'//cexpnr,position='append')
      write(ifoutput,'(//A,/A,F5.0,A,I4,A,I2,A,I2,A)') &
      '#--------------------------------------------------------'      &
      ,'#',(timeav),'--- AVERAGING TIMESTEP --- '      &
      ,nhrs,':',nminut,':',nsecs      &
      ,'   HRS:MIN:SEC AFTER INITIALIZATION '
      write (ifoutput,'(A/2A/2A)') &
          '#--------------------------------------------------------' &
          ,'#LEV HGHT     LW_UP        LW_DN        SW_NET       ' &
          ,'TL_LW_TEND   TL_SW_TEND   TL_LS_TEND' &
          ,'#    (M)      (W/M^2)      (W/M^2)      (W/M^2)      ' &
          ,'(K/H)         (K/H)        (K/H)'
      do k=1,kmax
        write(ifoutput,'(I3,F8.2,6E13.4)') &
            k,zf(k),&
            lwumn(k),&
            lwdmn(k),&
            swnmn(k),&
            tllwtendmn(k)*3600,&
            tlswtendmn(k)*3600,&
            tlradlsmn(k) *3600
      end do
      close (ifoutput)

    end if ! end if(myid==0)

    lwumn = 0.0
    lwdmn = 0.0
    swnmn = 0.0
    tllwtendmn = 0.0
    tlswtendmn = 0.0
    tlradlsmn  = 0.0


  end subroutine writeradstat


  subroutine exitradstat
    implicit none

    !deallocate variables that are needed in modradiation
    deallocate(lwdavl,lwuavl,swnavl,tllwtendavl,tlswtendavl)

    if(.not.(lstat)) return

    deallocate(lwuav,lwdav,swnav)
    deallocate(tllwtendav,tlswtendav)
    deallocate(lwumn,lwdmn,swnmn)
    deallocate(tllwtendmn,tlswtendmn,tlradlsmn)



  end subroutine exitradstat


end module modradstat
