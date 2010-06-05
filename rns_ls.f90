!**********************************************************************
module rns_ls
!**********************************************************************
use rns_base_ls
!!$if($CYL_SKEW_LS)
!!use cyl_skew_base_ls, only : tr_t, clindx_to_loc_id, brindx_to_loc_id, ntree
!!use cyl_skew_ls, only : cyl_skew_fill_tree_array_ls, ngen, ngen_reslv
!!!use cyl_skew_ls, only : cyl_skew_fill_cl_ref_plane_array_ls
!!!use cyl_skew_ls, only : cyl_skew_get_branch_id_ls
!!$endif

implicit none

save
private

public :: rns_CD_ls
public :: rns_forcing_ls ! Apply forcing
public :: rns_finalize_ls

character (*), parameter :: mod_name = 'rns_ls'

!**********************************************************************
contains
!**********************************************************************

!**********************************************************************
subroutine rns_CD_ls()
!**********************************************************************
!  This subroutine handles all CD calculation within the RNS module; 
!  all CD and force calculations associated with
!
!  tree -> generation -> cluster -> branch
!
!  are handled here
!
use param, only : jt, USE_MPI, coord
use messages
!!$if($CYL_SKEW_LS)
!!use cyl_skew_base_ls, only : ngen, ngen_reslv
!!$endif
implicit none

character (*), parameter :: sub_name = mod_name // '.rns_CD_ls'

!if(coord == 0) call mesg(sub_name, 'Entered ' // sub_name)

!if(clforce_calc) then

  call cl_force_ls()     !  Get CD, force etc for resolved regions
  call beta_force_ls()  !  Get force of 
    
  !if(ngen > ngen_reslv) call rns_cl_unreslv_CD_ls()
    
  if(modulo (jt, clforce_nskip) == 0) then
    
    if(.not. USE_MPI .or. (USE_MPI .and. coord == 0) ) then

      call write_cl_CD_ls()
      call write_cl_fD_ls()
      call write_cl_vel_ls()
      
      call write_beta_CD_ls()
      call write_beta_fD_ls()
      call write_beta_vel_ls()
      call write_beta_kappa_ls()
      
    endif
    
  endif
  
!endif

!if(coord == 0) call mesg(sub_name, 'Exiting ' // sub_name)

return
end subroutine rns_CD_ls


!**********************************************************************
subroutine cl_force_ls()
!**********************************************************************
!  This subroutine computes the CD of the branch cluster (cl) associated
!  with each region dictated by the brindx value. The cl is mapped from 
!  brindex
!
use types, only : rprec
!!use param, only : nx, ny, nz, dx, dy, dz
!!use param, only : USE_MPI, coord
!!$if($MPI)
!!use param, only : MPI_RPREC, MPI_SUM, rank_of_coord, comm, ierr
!!$endif
!!use sim_param, only : u
!!use functions, only : plane_avg_3D
!!use level_set_base, only : phi
!!use immersedbc, only : fx
$if($CYL_SKEW_LS)
use cyl_skew_base_ls, only : ntree, tr_t
$endif
use messages
use param, only : nx, ny, nz, dx, dy, dz, coord, USE_MPI
$if($MPI)
use param, only : MPI_RPREC, MPI_SUM, comm, ierr
$endif
use sim_param, only : u
use functions, only : plane_avg_3D
use immersedbc, only : fx
implicit none

character (*), parameter :: sub_name = mod_name // '.rns_cl_force_ls'

integer, pointer :: clindx_p
integer, pointer :: npoint_p
integer, pointer, dimension(:,:) :: iarray_p
integer, pointer :: i, j, k
real(rprec), pointer :: fD_p

integer :: ncluster_tot
integer :: nt, ng, nc, np

$if ($MPI)
real(rprec) :: cl_fD
$endif

!if(coord == 0) call mesg(sub_name, 'Entered ' // sub_name)

!  Comment starts here 
nullify(clindx_p)
nullify(npoint_p, iarray_p)
nullify(i,j,k)
nullify(fD_p)

!!$if ($MPI)
!!allocate (cl_fD ( ncluster_reslv_ref ) )
!!cl_fD = 0._rprec
!!$endif

do nt = 1, rns_ntree

  do ng = 1, tr_t(nt) % ngen_reslv
  
    do nc = 1, tr_t(nt) % gen_t(ng) % ncluster
    
      clindx_p => rns_reslv_cl_iarray(tr_t(nt) % gen_t(ng) % cl_t(nc) % indx)

!      write(*,'(1a,5i4)') 'coord, nt, ng, nc, clindx : ', coord, nt, ng, nc, clindx_p
   
      cl_ref_plane_t(clindx_p) % u = plane_avg_3D( u(1:nx,:,1:nz), cl_ref_plane_t(clindx_p) % p1, cl_ref_plane_t(clindx_p) % p2, &
        cl_ref_plane_t(clindx_p) % p3, cl_ref_plane_t(clindx_p) % nzeta, cl_ref_plane_t(clindx_p) % neta )
     
      npoint_p => cl_indx_array_t(clindx_p) % npoint
      iarray_p => cl_indx_array_t(clindx_p) % iarray

!     write(*,'(1a,2i4)') 'coord, npoint : ', coord, npoint_p
  
      $if($MPI)
      cl_fD = 0._rprec
      $endif
  !clforce_t(clindx_p) % fD = 0._rprec
  
      fD_p => clforce_t( clindx_p ) % fD
      fD_p = 0._rprec
  
      do np=1, npoint_p
  
        i => iarray_p(1,np)
        j => iarray_p(2,np)
        k => iarray_p(3,np)
  
        $if($MPI)
        cl_fD = cl_fD + fx(i,j,k) * dx * dy * dz
        $else
        fD_p = fD_p + fx(i,j,k) * dx * dy * dz
        $endif
    
        nullify(i,j,k)
    
      enddo
  
      $if($MPI)
      call mpi_allreduce (cl_fD, fD_p, 1, MPI_RPREC, MPI_SUM, comm, ierr)
      $endif
  
      clforce_t(clindx_p) % CD = -fD_p / (0.5_rprec * cl_ref_plane_t(clindx_p)%area * (cl_ref_plane_t(clindx_p)%u)**2)
  
      nullify(clindx_p)
      nullify(npoint_p, iarray_p)
      nullify(fD_p)
 
      
    enddo
    
  enddo
 
enddo

!  Comment ends here

!do nc = 1, ncluster_reslv_ref
!  reslv_cl_loc_id_p => reslv_clindx_to_loc_id(:,nc)
!  clindx_p => tr_t(reslv_cl_loc_id_p(1)) % gen_t(reslv_cl_loc_id_p(2)) % cl_t(reslv_cl_loc_id_p(3)) % indx
!  clforce_t(clindx_p) % CD = 1._rprec
!  nullify(reslv_cl_loc_id_p, clindx_p)
!      
!enddo

!if(use_main_tree_ref) then
!!  Need to put CD on other resolved clusters (on other trees)
!  do nt = 2, ntree
!    do ng = 1, tr_t(nt) % ngen_reslv
!      do nc = 1, tr_t(nt) % gen_t (ng) % ncluster

!        clindx_p       => tr_t(1) % gen_t(ng) % cl_t(nc) % indx
!        clindx_other_p => tr_t(nt) % gen_t(ng) % cl_t(nc) % indx
!        
!        clforce_t(clindx_other_p) % CD = clforce_t(clindx_p) % CD
!        
!        nullify(clindx_p, clindx_other_p)
!        
!      enddo
!    enddo
!  enddo
!  
!endif

!if(coord == 0) call mesg(sub_name, 'Exiting ' // sub_name)

return
end subroutine cl_force_ls

!**********************************************************************
subroutine beta_force_ls()
!**********************************************************************
!  This subroutine computes the CD of the branch cluster (cl) associated
!  with each region dictated by the brindx value. 
!
use types, only : rprec
use param, only : dx, dy, dz, nx, ny, nz, jt, coord, USE_MPI
use messages
use sim_param, only : u
use immersedbc, only : fx
use functions, only : plane_avg_3D
$if($MPI)
use mpi
use param, only : MPI_RPREC, MPI_SUM, comm, ierr
$endif
$if($CYL_SKEW_LS)
use cyl_skew_base_ls, only : tree, generation, tr_t
$endif
implicit none

character (*), parameter :: sub_name = mod_name // '.rns_beta_force_ls'

integer :: nb, np, nt, nc
integer :: ib, irb

integer, pointer :: i,j,k
integer, pointer :: npoint_p
integer, pointer :: clindx_p
integer, pointer :: rbeta_indx_p, rns_clindx_p

real(rprec), pointer, dimension(:) :: p1_p, p2_p, p3_p   
integer, pointer :: nzeta_p, neta_p 
real(rprec), pointer :: area_p, u_p
real(rprec), pointer :: kappa_p, CD_p

!real(rprec) :: sigma
!real(rprec), allocatable, dimension(:) :: fD_dir

real(rprec) :: CD_num, CD_denom, CD, Lint

real(rprec), allocatable, dimension(:) ::  fD_tot, CD_rbeta

$if($MPI)
real(rprec) :: Lint_global
$endif

type(tree), pointer :: tr_t_p
type(generation), pointer :: gen_t_p

$if($MPI)
real(rprec) :: fD
$endif

!if(coord == 0) call mesg(sub_name, 'Entered ' // sub_name)

nullify(i,j,k)
nullify(npoint_p)
nullify(clindx_p)
nullify(rbeta_indx_p, rns_clindx_p)

nullify(p1_p, p2_p, p3_p)
nullify(nzeta_p, neta_p)
nullify(area_p, u_p)
nullify(kappa_p, CD_p)

nullify(tr_t_p)
nullify(gen_t_p)

!allocate(fD_dir(nbeta))

!  Compute total drag force all unresolved (beta) regions
!  Need more work to have beta as sub regions

!  Step 0: Get the total force due to each beta region
do ib = 1, nbeta 
 
  !  Loop over number of points used in beta region
  npoint_p => beta_indx_array_t( ib ) % npoint
  
  $if($MPI)
  fD = 0._rprec
  $endif
  
  beta_force_t(ib) % fD = 0._rprec
  
  do np = 1, npoint_p
  
    i => beta_indx_array_t( ib ) % iarray(1,np)
    j => beta_indx_array_t( ib ) % iarray(2,np)
    k => beta_indx_array_t( ib ) % iarray(3,np)
    
    $if($MPI)
    fD = fD + fx(i,j,k) * dx * dy * dz
    $else    
    beta_force_t(ib) % fD = beta_force_t(ib) % fD + fx(i,j,k) * dx * dy * dz
    $endif
 
    nullify(i,j,k)
    
  enddo
  
  $if($MPI)
  call mpi_allreduce (fD, beta_force_t(ib) % fD, 1, MPI_RPREC, MPI_SUM, comm, ierr)
  $endif
  
  nullify(npoint_p)

  !if(beta_force_t(nb) % fD < 0._rprec) then

  !  fD_dir(nb) = -1._rprec

  !else

  !  fD_dir(nb) = 1._rprec

  !endif
  
enddo
  
allocate(fD_tot(nrbeta))
fD_tot = 0._rprec
  
! Step 1: Sum the force for each of the beta regions
do ib = 1, nbeta
  
  rbeta_indx_p => beta_force_t(ib) % parent
    
  fD_tot( rbeta_indx_p ) = fD_tot(rbeta_indx_p) + beta_force_t(ib) % fD
    
  nullify(rbeta_indx_p)
    
enddo
  
  !  Step 2: Sum the force due to the resolved clusters
do nt = 1, rns_ntree
  
  tr_t_p => tr_t( rns_tree_iarray(nt) )
  gen_t_p => tr_t_p % gen_t ( tr_t_p % ngen_reslv )
   
  do nc = 1, gen_t_p % ncluster
    
    clindx_p => gen_t_p % cl_t (nc) % indx
           
    rbeta_indx_p => rns_rbeta_iarray( clindx_p )
    rns_clindx_p => rns_reslv_cl_iarray( clindx_p ) 
      
    !if(coord == 0) write(*,*) 'clindx_p, rbeta_indx_p, rns_clindx_p : ', clindx_p, rbeta_indx_p, rns_clindx_p
      
    fD_tot(rbeta_indx_p) = fD_tot(rbeta_indx_p) + clforce_t(rns_clindx_p) % fD
      
    nullify(clindx_p, rbeta_indx_p, rns_clindx_p)
      
  enddo
    
  nullify(tr_t_p, gen_t_p)
    
enddo

if(use_single_beta_CD) then  

  CD_num = 0._rprec
  CD_denom = 0._rprec
 
  !  Step 3: Get reference quantities and sum  
  do irb = 1, nrbeta

    !tr_t_p => tr_t(rns_tree_iarray(nt))
    !!gen_t_p => tr_t_p % gen_t ( tr_t_p % ngen_reslv )
    
    !do nc = 1, gen_t_p % ncluster
    
    !  clindx_p => gen_t_p % cl_t (nc) % indx
    !  
    !  rbeta_indx_p => rns_rbeta_iarray(clindx_p)
  
    p1_p    => rbeta_ref_plane_t (irb) % p1
    p2_p    => rbeta_ref_plane_t (irb) % p2
    p3_p    => rbeta_ref_plane_t (irb) % p3
    nzeta_p => rbeta_ref_plane_t (irb) % nzeta
    neta_p  => rbeta_ref_plane_t (irb) % neta
    area_p  => rbeta_ref_plane_t (irb) % area
    u_p     => rbeta_ref_plane_t (irb) % u

    u_p = plane_avg_3D(u(1:nx,1:ny,1:nz), p1_p, p2_p, p3_p, nzeta_p, neta_p)
  
    nullify(p1_p, p2_p, p3_p, nzeta_p, neta_p)
      
    CD_num = CD_num + fD_tot(irb) * u_p * dabs( u_p ) * area_p
    CD_denom = CD_denom + u_p * u_p * u_p * u_p * area_p**2
    
    nullify(area_p, u_p)

  enddo

  !  Compute CD
  CD = -2._rprec * CD_num / CD_denom
  
  if( jt < CD_ramp_nstep ) CD = dble(jt)/dble(CD_ramp_nstep) * CD
  
  !  This CD goes with the regions beta on all trees ! and is the new CD
  do ib = 1, nbeta
  
    beta_force_t( ib ) % CD = CD
    
  enddo
  
else

  allocate(CD_rbeta(nrbeta))
  CD_rbeta=0._rprec

!  Each rbeta region will get a CD
    
  !  Step 3: Get reference quantities and sum  
  do irb = 1, nrbeta
  
    CD_num = 0._rprec
    CD_denom = 0._rprec
  
    !tr_t_p => tr_t(rns_tree_iarray(nt))
    !!gen_t_p => tr_t_p % gen_t ( tr_t_p % ngen_reslv )
    
    !do nc = 1, gen_t_p % ncluster
    
    !  clindx_p => gen_t_p % cl_t (nc) % indx
    !  
    !  rbeta_indx_p => rns_rbeta_iarray(clindx_p)
  
    p1_p    => rbeta_ref_plane_t (irb) % p1
    p2_p    => rbeta_ref_plane_t (irb) % p2
    p3_p    => rbeta_ref_plane_t (irb) % p3
    nzeta_p => rbeta_ref_plane_t (irb) % nzeta
    neta_p  => rbeta_ref_plane_t (irb) % neta
    area_p  => rbeta_ref_plane_t (irb) % area
    u_p     => rbeta_ref_plane_t (irb) % u

    u_p = plane_avg_3D(u(1:nx,1:ny,1:nz), p1_p, p2_p, p3_p, nzeta_p, neta_p)
  
    nullify(p1_p, p2_p, p3_p, nzeta_p, neta_p)
      
    CD_num = fD_tot(irb) * u_p * dabs( u_p ) * area_p
    CD_denom = u_p * u_p * u_p * u_p * area_p**2
    
    CD_rbeta(irb) = -2._rprec * CD_num / CD_denom
    
    if( jt < CD_ramp_nstep ) CD_rbeta(irb) = dble(jt)/dble(CD_ramp_nstep) * CD_rbeta(irb)
    
    nullify(area_p, u_p)

  enddo

  !  This CD goes with the regions rbeta 
  do ib = 1, nbeta

    beta_force_t( ib ) % CD = CD_rbeta ( beta_force_t ( ib ) % parent )
    
  enddo
  
  deallocate(CD_rbeta)

endif

deallocate(fD_tot)

  
!  Compute kappa
!  Compute Lint over each region beta

do ib = 1, nbeta 
  
  p1_p    => beta_ref_plane_t (ib) % p1
  p2_p    => beta_ref_plane_t (ib) % p2
  p3_p    => beta_ref_plane_t (ib) % p3
  nzeta_p => beta_ref_plane_t (ib) % nzeta
  neta_p  => beta_ref_plane_t (ib) % neta
  area_p  => beta_ref_plane_t (ib) % area
  u_p     => beta_ref_plane_t (ib) % u
    
  u_p = plane_avg_3D(u(1:nx,1:ny,1:nz), p1_p, p2_p, p3_p, nzeta_p, neta_p)
  
  nullify(p1_p, p2_p, p3_p, nzeta_p, neta_p)  
 
  !  Loop over number of points used in beta region
  npoint_p => beta_indx_array_t( ib ) % npoint
    
  Lint = 0._rprec
    
  $if($MPI)
  Lint_global = 0._rprec
  $endif
  
  do np = 1, npoint_p
  
    i => beta_indx_array_t( ib ) % iarray(1,np)
    j => beta_indx_array_t( ib ) % iarray(2,np)
    k => beta_indx_array_t( ib ) % iarray(3,np)
    
    Lint = Lint + dabs( u(i,j,k) ) * u(i,j,k) * chi(i,j,k) 
 
    nullify(i,j,k)
      
  enddo
    
  nullify( npoint_p )
    
  $if($MPI)
  call mpi_allreduce (Lint, Lint_global, 1, MPI_RPREC, MPI_SUM, comm, ierr)
  Lint = Lint_global
  $endif
    
  kappa_p => beta_force_t(ib) % kappa
  CD_p    => beta_force_t(ib) % CD
    
  kappa_p = CD_p * dabs ( u_p ) * area_p * u_p / ( 2._rprec * Lint * dx * dy * dz )
    
  if(coord == 0 .and. (modulo (jt, clforce_nskip) == 0)) write(*,'(1a,i3,3f18.6)') 'beta, kappa, CD, Lint : ', ib, kappa_p, CD_p, Lint
    
  nullify(kappa_p, CD_p)
  nullify(u_p, area_p)
        
enddo
   
  

  
!deallocate(fD_dir)

end subroutine beta_force_ls

!**********************************************************************
subroutine rns_forcing_ls()
!**********************************************************************
!  This subroutine computes the forces on the unresolved branches
!
use types, only : rprec
use sim_param, only : u
use immersedbc, only : fx
$if($MPI)
use mpi
use param, only : MPI_RPREC, up, down, comm, status, ierr, ld, ny, nz, nproc
use mpi_defs, only : mpi_sync_real_array
$endif
use param, only : dx, dy, dz, coord, jt, USE_MPI

implicit none

character (*), parameter :: sub_name = mod_name // '.rns_forcing_ls'

integer :: ib, np

integer, pointer :: i, j, k

integer, pointer :: npoint_p

real(rprec), pointer :: kappa_p

nullify(i,j,k)
nullify(npoint_p)
nullify(kappa_p)


do ib = 1, nbeta 
 
    !  Loop over number of points used in beta region
    npoint_p => beta_indx_array_t( ib ) % npoint
    
    kappa_p  => beta_force_t( ib ) % kappa
  
    do np = 1, npoint_p
  
      i => beta_indx_array_t( ib ) % iarray(1,np)
      j => beta_indx_array_t( ib ) % iarray(2,np)
      k => beta_indx_array_t( ib ) % iarray(3,np)
    
      fx(i,j,k) = - kappa_p * dabs( u(i,j,k) ) * u(i,j,k) * chi(i,j,k) 
 
      nullify(i,j,k)
      
    enddo
    
    nullify( npoint_p, kappa_p )
    
enddo

$if($MPI)
!  Sync data at overlap nodes
!if(coord < nproc - 1) then
!  call mpi_recv (fx(:,:,nz), ld*ny, MPI_RPREC, up, 1, comm, status, ierr)
!endif
!if(coord > 0) then
!  call mpi_send (fx(:,:,1), ld*ny, MPI_RPREC, down, 1, comm, ierr)
!endif
call mpi_sync_real_array( fx )
$endif

return

end subroutine rns_forcing_ls


!**********************************************************************
subroutine write_cl_CD_ls()
!**********************************************************************
use io, only : write_real_data, write_tecplot_header_xyline
use param, only : total_time, dt, path
use strmod
$if($CYL_SKEW_LS)
use cyl_skew_base_ls, only :  reslv_clindx_to_loc_id
$endif

implicit none

character(*), parameter :: sub_name = mod_name // '.write_cl_CD_ls'
character(*), parameter :: fname = path // 'output/rns_cl_CD_ls.dat'

logical :: exst
character(5000) :: var_list
integer :: nc, nvar, nvar_count
integer, pointer, dimension(:) :: reslv_cl_loc_id_p => null()

!  Write cluster force (CD) for all trees + time step

nvar = ncluster_reslv + 1

inquire (file=fname, exist=exst)
if (.not. exst) then
  var_list = '"t"'
  do nc = 1, nvar-1
  
    reslv_cl_loc_id_p => reslv_clindx_to_loc_id(:,nc)
    !  Create variable list name:
    call strcat(var_list, ',"CD<sub>')
    call strcat(var_list, reslv_cl_loc_id_p(1))
    call strcat(var_list, ',')
    call strcat(var_list, reslv_cl_loc_id_p(2))
    call strcat(var_list, ',')
    call strcat(var_list, reslv_cl_loc_id_p(3))
    call strcat(var_list, '</sub>"')
  enddo
  nullify(reslv_cl_loc_id_p)
  call write_tecplot_header_xyline(fname, 'rewind', trim(adjustl(var_list)))
endif

call write_real_data(fname, 'append', 'formatted', nvar, (/ total_time, clforce_t(1:nvar-1)%CD /))

return
end subroutine write_cl_CD_ls

!**********************************************************************
subroutine write_cl_vel_ls()
!**********************************************************************
use io, only : write_real_data, write_tecplot_header_xyline
use param, only : total_time, dt, path
use strmod
$if($CYL_SKEW_LS)
use cyl_skew_base_ls, only :  reslv_clindx_to_loc_id
$endif

implicit none

character(*), parameter :: sub_name = mod_name // '.write_cl_vel_ls'
character(*), parameter :: fname = path // 'output/rns_cl_vel_ls.dat'

logical :: exst
character(5000) :: var_list
integer :: nc, nvar, nvar_count
integer, pointer, dimension(:) :: reslv_cl_loc_id_p => null()

!  Write cluster force (CD) for all trees + time step

nvar = ncluster_reslv + 1

inquire (file=fname, exist=exst)
if (.not. exst) then
  var_list = '"t"'
  do nc = 1, nvar-1
  
    reslv_cl_loc_id_p => reslv_clindx_to_loc_id(:,nc)
    !  Create variable list name:
    call strcat(var_list, ',"u<sub>')
    call strcat(var_list, reslv_cl_loc_id_p(1))
    call strcat(var_list, ',')
    call strcat(var_list, reslv_cl_loc_id_p(2))
    call strcat(var_list, ',')
    call strcat(var_list, reslv_cl_loc_id_p(3))
    call strcat(var_list, '</sub>"')
  enddo
  nullify(reslv_cl_loc_id_p)
  call write_tecplot_header_xyline(fname, 'rewind', trim(adjustl(var_list)))
endif

call write_real_data(fname, 'append', 'formatted', nvar, (/ total_time, cl_ref_plane_t(1:nvar-1)%u /))

return
end subroutine write_cl_vel_ls

!**********************************************************************
subroutine write_beta_vel_ls()
!**********************************************************************
use io, only : write_real_data, write_tecplot_header_xyline
use param, only : total_time, dt, path
use strmod

implicit none

character(*), parameter :: sub_name = mod_name // '.write_beta_vel_ls'
character(*), parameter :: fname = path // 'output/rns_beta_vel_ls.dat'

logical :: exst
character(5000) :: var_list
integer :: nc, nvar, nvar_count

!  Write cluster force (CD) for all trees + time step
nvar = nbeta + 1

inquire (file=fname, exist=exst)
if (.not. exst) then
  var_list = '"t"'
  do nc = 1, nvar-1
  
    !  Create variable list name:
    call strcat(var_list, ',"u<sub>')
    call strcat(var_list, nc)
    call strcat(var_list, ',')
    call strcat(var_list, 1) ! Need ability to specify beta region
    call strcat(var_list, '</sub>"')
  enddo

  call write_tecplot_header_xyline(fname, 'rewind', trim(adjustl(var_list)))
endif

call write_real_data(fname, 'append', 'formatted', nvar, (/ total_time, beta_ref_plane_t(1:nvar-1) % u /))

return
end subroutine write_beta_vel_ls

!**********************************************************************
subroutine write_cl_fD_ls()
!**********************************************************************
use io, only : write_real_data, write_tecplot_header_xyline
use param, only : total_time, dt, path
use strmod
$if($CYL_SKEW_LS)
use cyl_skew_base_ls, only :  reslv_clindx_to_loc_id
$endif

implicit none

character(*), parameter :: sub_name = mod_name // '.write_cl_fD_ls'
character(*), parameter :: fname = path // 'output/rns_cl_fD_ls.dat'

logical :: exst
character(5000) :: var_list
integer :: nc, nvar, nvar_count
integer, pointer, dimension(:) :: reslv_cl_loc_id_p => null()

!  Write cluster force (CD) for all trees + time step

nvar = ncluster_reslv + 1

inquire (file=fname, exist=exst)
if (.not. exst) then
  var_list = '"t"'
  do nc = 1, nvar-1
  
    reslv_cl_loc_id_p => reslv_clindx_to_loc_id(:,nc)
    !  Create variable list name:
    call strcat(var_list, ',"fD<sub>')
    call strcat(var_list, reslv_cl_loc_id_p(1))
    call strcat(var_list, ',')
    call strcat(var_list, reslv_cl_loc_id_p(2))
    call strcat(var_list, ',')
    call strcat(var_list, reslv_cl_loc_id_p(3))
    call strcat(var_list, '</sub>"')
  enddo
  nullify(reslv_cl_loc_id_p)
  call write_tecplot_header_xyline(fname, 'rewind', trim(adjustl(var_list)))
endif

call write_real_data(fname, 'append', 'formatted', nvar, (/ total_time, -clforce_t(1:nvar-1)%fD /))

return
end subroutine write_cl_fD_ls

!**********************************************************************
subroutine write_beta_fD_ls()
!**********************************************************************
use io, only : write_real_data, write_tecplot_header_xyline
use param, only : total_time, dt, path
use strmod

implicit none

character(*), parameter :: sub_name = mod_name // '.write_beta_fD_ls'
character(*), parameter :: fname = path // 'output/rns_beta_fD_ls.dat'

logical :: exst
character(5000) :: var_list
integer :: nc, nvar, nvar_count

!  Write cluster force (CD) for all trees + time step
nvar = nbeta + 1

inquire (file=fname, exist=exst)
if (.not. exst) then
  var_list = '"t"'
  do nc = 1, nvar-1
  
    !  Create variable list name:
    call strcat(var_list, ',"fD<sub>')
    call strcat(var_list, nc)
    call strcat(var_list, ',')
    call strcat(var_list, 1) ! Need ability to specify beta region
    call strcat(var_list, '</sub>"')
  enddo

  call write_tecplot_header_xyline(fname, 'rewind', trim(adjustl(var_list)))
endif

call write_real_data(fname, 'append', 'formatted', nvar, (/ total_time, -beta_force_t(1:nvar-1) % fD /))

return
end subroutine write_beta_fD_ls

!**********************************************************************
subroutine write_beta_CD_ls()
!**********************************************************************
use io, only : write_real_data, write_tecplot_header_xyline
use param, only : total_time, dt, path
use strmod

implicit none

character(*), parameter :: sub_name = mod_name // '.write_beta_CD_ls'
character(*), parameter :: fname = path // 'output/rns_beta_CD_ls.dat'

logical :: exst
character(5000) :: var_list
integer :: nc, nvar, nvar_count

!  Write cluster force (CD) for all trees + time step
nvar = nbeta + 1

inquire (file=fname, exist=exst)
if (.not. exst) then
  var_list = '"t"'
  do nc = 1, nvar-1
  
    !  Create variable list name:
    call strcat(var_list, ',"CD<sub>')
    call strcat(var_list, nc)
    call strcat(var_list, ',')
    call strcat(var_list, 1) ! Need ability to specify beta region
    call strcat(var_list, '</sub>"')
  enddo

  call write_tecplot_header_xyline(fname, 'rewind', trim(adjustl(var_list)))
endif

call write_real_data(fname, 'append', 'formatted', nvar, (/ total_time, beta_force_t(1:nvar-1) % CD /))

return
end subroutine write_beta_CD_ls

!**********************************************************************
subroutine write_beta_kappa_ls()
!**********************************************************************
use io, only : write_real_data, write_tecplot_header_xyline
use param, only : total_time, dt, path
use strmod

implicit none

character(*), parameter :: sub_name = mod_name // '.write_beta_kappa_ls'
character(*), parameter :: fname = path // 'output/rns_beta_kappa_ls.dat'

logical :: exst
character(5000) :: var_list
integer :: nc, nvar, nvar_count

!  Write cluster force (CD) for all trees + time step
nvar = nbeta + 1

inquire (file=fname, exist=exst)
if (.not. exst) then
  var_list = '"t"'
  do nc = 1, nvar-1
  
    !  Create variable list name:
    call strcat(var_list, ',"<greek>k</greek><sub>')
    call strcat(var_list, nc)
    call strcat(var_list, ',')
    call strcat(var_list, 1) ! Need ability to specify beta region
    call strcat(var_list, '</sub>"')
  enddo

  call write_tecplot_header_xyline(fname, 'rewind', trim(adjustl(var_list)))
endif

call write_real_data(fname, 'append', 'formatted', nvar, (/ total_time, beta_force_t(1:nvar-1) % kappa /))

return
end subroutine rns_write_beta_kappa_ls

!**********************************************************************
subroutine rns_force_init_ls ()
!**********************************************************************
!  
!  This subroutine reads the last BETA force data from a previous simulation
!
use param, only : coord, USE_MPI
use messages
implicit none

character (*), parameter :: sub_name = mod_name // '.rns_force_init_ls'
character (*), parameter :: fname_in = 'rns_force_ls.out'
$if ($MPI)
  character (*), parameter :: MPI_suffix = '.c'

  character (128) :: fname
$endif

integer :: ip

logical :: opn, exst

!---------------------------------------------------------------------

inquire (unit=1, opened=opn)
if (opn) call error (sub_name, 'unit 1 already open')

$if ($MPI)
write (fname, '(a,a,i0)') fname_in, MPI_suffix, coord
$else
fname = trim(adjustl(fname_in))
$endif

inquire (file=fname, exist=exst)

if (.not. exst) then
  if(.not. USE_MPI .or. (USE_MPI .and. coord == 0)) then
    write(*,*) ' '
    write(*,*)'No previous RNS force data - starting from scratch.'
  endif
  return ! Do nothing if not present
endif 

open (1, file=fname, action='read', position='rewind',  &
  form='unformatted')
read (1) beta_force_t
close (1)

end subroutine rns_force_init_ls

!**********************************************************************
subroutine rns_finalize_ls()
!**********************************************************************
! 
!  This subroutine writes all restart data to file
!
use param, only : coord
use messages
implicit none

character (*), parameter :: sub_name = mod_name // '.rns_finalize_ls'
character (*), parameter :: fname_out = 'rns_force_ls.out'
$if ($MPI)
  character (*), parameter :: MPI_suffix = '.c'

  character (128) :: fname
$endif

integer :: ip

logical :: opn, exst

!---------------------------------------------------------------------

inquire (unit=1, opened=opn)
if (opn) call error (sub_name, 'unit 1 already open')

$if ($MPI)
write (fname, '(a,a,i0)') fname_out, MPI_suffix, coord
$else
fname = trim(adjustl(fname_out))
$endif

open (1, file=fname, action='write', position='rewind',  &
  form='unformatted')
write (1) beta_force_t
close (1)

return
end subroutine rns_finalize_ls

end module rns_ls


