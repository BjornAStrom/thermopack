module multiparameter_para_h2
  !> Parahydrogen multiparameter fundamental equation for Helmholtz energy. See
  !> Leachman et al. (2009), doi:10.1063/1.3160306.
  use multiparameter_base, only: meos
  implicit none
  save
  public :: meos_para_h2
  private

  ! Parameters for the ideal gas part alpha^0
  real, parameter, dimension(1:2) :: a = (/ -1.4485891134, 1.884521239 /)
  real, parameter, dimension(3:9) :: b = (/  -15.1496751472, -25.0925982148, &
       -29.4735563787, -35.4059141417, -40.724998482, -163.7925799988, -309.2173173842/)
  real, parameter, dimension(3:9) :: v = (/&
       4.30256,&
       13.0289,&
       -47.7365 ,&
       50.0013 ,&
       -18.6261 ,&
       0.993973 ,&
       0.536078/)

  ! upPol is the upper index for polynomial terms, upExp the same for
  ! single-expontential terms, upExpExp for double-exponential terms.
  integer, parameter :: upPol = 7
  integer, parameter :: upExp = 9
  integer, parameter :: upExpExp = 14

  real, parameter, dimension(1:upPol) :: N_pol = (/ &
       -7.33375 ,&
       0.01 ,&
       2.60375  ,&
       4.66279  ,&
       0.682390  ,&
       -1.47078  ,&
       0.135801/)
  real, parameter, dimension(upPol+1:upExp) :: N_exp =(/-1.05327, 0.328239 /)

  real, parameter, dimension(upExp+1:upExpExp) :: N_expexp = (/ &
       -0.0577833 ,&
       0.0449743 ,&
       0.0703464 ,&
       -0.0401766 ,&
       0.119510/)

  real, parameter, dimension(1:upPol) :: t_pol = (/ 0.6855, 1.0, 1.0, 0.489, 0.774, 1.133, 1.386 /)
  real, parameter, dimension(upPol+1:upExp) :: t_exp = (/ 1.619, 1.162 /)

  real, parameter, dimension(upExp+1:upExpExp) :: t_expexp = (/ 3.96, 5.276, 0.99, 6.791, 3.19 /)

  integer, parameter, dimension(1:upPol) :: d_pol = (/1  ,4  ,1  ,1  ,2  ,2  ,3  /)
  integer, parameter, dimension(upPol+1:upExp) :: d_exp = (/1,3/)
  integer, parameter, dimension(upExp+1:upExpExp) :: d_expexp = (/2,1,3,1,1/)

  integer, parameter, dimension(upPol+1:upExp) :: l_exp = (/1,1/)

  real, parameter, dimension(upExp+1:upExpExp) :: eta_expexp = (/&
       1.7437 ,&
       0.5516 ,&
       0.0634 ,&
       2.1341 ,&
       1.777 /)

  real, parameter, dimension(upExp+1:upExpExp) :: beta_expexp = (/&
       0.194 ,&
       0.2019 ,&
       0.0301 ,&
       0.2383 ,&
       0.3253 /)

  real, parameter, dimension(upExp+1:upExpExp) :: gam_expexp = (/&
       0.8048 ,&
       1.5248 ,&
       0.6648 ,&
       0.6832 ,&
       1.493/)

  real, parameter, dimension(upExp+1:upExpExp) :: eps_expexp = (/&
       1.5487 ,&
       0.1785 ,&
       1.28 ,&
       0.6319 ,&
       1.7104 /)

  type, extends(meos) :: meos_para_h2
     private
     ! Cache the expensive temperature-dependent quantities.
     real :: tau_cache
     real :: deltaSatLiq_cache
     real :: deltaSatVap_cache
     real :: prefactors_pol_cache(1:upPol)
     real :: prefactors_exp_cache(upPol+1:upExp)
     real :: prefactors_expexp_cache(upExp+1:upExpExp)

   contains

     procedure, public :: alpha0Derivs_taudelta => alpha0Derivs_PARA_H2
     procedure, public :: alphaResDerivs_taudelta => alphaResDerivs_PARA_H2
     procedure, public :: satDeltaEstimate => satDeltaEstimate_PARA_H2
     procedure, public :: init => init_PARA_H2

     procedure, private :: alphaResPrefactors => alphaResPrefactors_PARA_H2

     ! Assignment operator
     procedure, pass(This), public :: assign_meos => assign_meos_para_h2

  end type meos_para_h2

contains

  subroutine init_PARA_H2 (this, use_Rgas_fit)
    class(meos_para_h2) :: this
    logical, optional, intent(in) :: use_Rgas_fit

    this%tau_cache = 0.0

    this%compName = "para_H2"

    this%molarMass = 2.01588e-3 !< (kg/mol) (Not stated in paper. From Coolprop.)
    this%Rgas_fit = 8.314472 !< (J/(mol*K))

    this%maxT = 1000.0 ! (T)
    this%maxP = 2000e6 ! (Pa)

    this%tc = 32.938   !< (K)
    this%pc = 1.2858e6 !< (Pa)
    this%rc = 15.538e3 !< (mol/m^3)
    this%acf = -0.219

    this%t_triple = 13.8033       !< (K)
    this%p_triple = 7041.0        !< (Pa)
    this%rhoLiq_triple = 38.185e3 !< (mol/m^3)
    this%rhoVap_triple = 0.12555/this%molarMass  !< (mol/m^3)

    if (present(use_Rgas_fit)) then
       if (use_Rgas_fit) then
          this%Rgas_meos = this%Rgas_fit
       end if
    end if

  end subroutine init_PARA_H2

  ! The functional form of the ideal gas function varies among multiparameter EoS,
  ! which explains why this routine may seem a bit hard-coded.
  subroutine alpha0Derivs_PARA_H2(this, delta, tau, alp0)
    class(meos_para_h2) :: this
    real, intent(in) :: delta, tau
    real, intent(out) :: alp0(0:2,0:2) !< alp0(i,j) = [(d_delta)^i(d_tau)^j alpha0]*delta^i*tau^j
    ! Internals
    real, dimension(3:9) :: exps

    exps = exp(b*tau)

    alp0 = 0.0
    alp0(0,0) = log(delta) + 1.5*log(tau) + a(1) + a(2)*tau + dot_product(v, log(1-exps))
    alp0(1,0) = 1.0
    alp0(2,0) = -1.0
    alp0(0,1) = 1.5 + a(2)*tau + tau*dot_product(v*b, exps/(exps-1))
    alp0(0,2) = -1.5 - tau*tau*dot_product(v*b**2, exps/(exps-1)**2)

  end subroutine alpha0Derivs_PARA_H2

  ! Supplies all prefactors that do not depend on delta. Prefactors are cached.
  subroutine alphaResPrefactors_PARA_H2 (this, tau, prefactors_pol, prefactors_exp, prefactors_expexp)
    class(meos_para_h2) :: this
    real, intent(in) :: tau
    real, intent(out) :: prefactors_pol(1:upPol)
    real, intent(out) :: prefactors_exp(upPol+1:upExp)
    real, intent(out) :: prefactors_expexp(upExp+1:upExpExp)

    if ( tau /= this%tau_cache ) then
       this%tau_cache = tau
       this%prefactors_pol_cache = N_pol * tau**t_pol
       this%prefactors_exp_cache = N_exp * tau**t_exp
       this%prefactors_expexp_cache = N_expexp * tau**t_expexp
    end if

    prefactors_pol = this%prefactors_pol_cache
    prefactors_exp = this%prefactors_exp_cache
    prefactors_expexp = this%prefactors_expexp_cache

  end subroutine alphaResPrefactors_PARA_H2


  subroutine alphaResDerivs_PARA_H2 (this, delta, tau, alpr)
    class(meos_para_h2) :: this
    real, intent(in) :: delta, tau
    real, intent(out) :: alpr(0:2,0:2) !< alpr(i,j) = (d_delta)^i(d_tau)^j alphaRes
    ! Internal
    real :: deltaL(upPol+1:upExp)
    real :: prefactors_pol(1:upPol)
    real :: prefactors_exp(upPol+1:upExp)
    real :: prefactors_expexp(upExp+1:upExpExp)
    real :: polTerms(1:upPol), expTerms(upPol+1:upExp), expExpTerms(upExp+1:upExpExp)
    call this%alphaResPrefactors(tau, prefactors_pol, prefactors_exp, prefactors_expexp)

    ! Precalculate polynomial terms
    polTerms(1:upPol) = prefactors_pol*delta**d_pol

    ! Precalculate single-exponential terms
    deltaL(upPol+1:upExp) = delta**l_exp
    expTerms(upPol+1:upExp) = prefactors_exp * delta**d_exp * exp(-deltaL)

    ! Precalculate double-exponential terms
    expExpTerms(upExp+1:upExpExp) = prefactors_expexp * delta**d_expexp &
         * exp(-eta_expexp*(delta-eps_expexp)**2 - beta_expexp*(tau-gam_expexp)**2)

    ! alpha
    alpr(0,0) = sum(polTerms) + sum(expTerms) + sum(expExpTerms)

    ! delta*alpha_delta
    alpr(1,0) = dot_product(polTerms, d_pol) + dot_product(expTerms, d_exp - l_exp*deltaL) &
         + dot_product(expExpTerms, d_expexp - 2*eta_expexp*delta*(delta-eps_expexp))

    ! delta**2 * alpha_deltadelta
    alpr(2,0) = dot_product(polTerms, d_pol*(d_pol-1)) + &
         dot_product(expTerms, (d_exp - l_exp*deltaL)*(d_exp-1-l_exp*deltaL) - l_exp*l_exp*deltaL ) + &
         dot_product(expExpTerms, (d_expexp - 2*eta_expexp*delta*(delta-eps_expexp))**2 - d_expexp - 2*eta_expexp*delta**2 )

    ! tau*alpha_tau
    alpr(0,1) = dot_product(polTerms, t_pol) + dot_product(expTerms, t_exp) &
         + dot_product(expExpTerms, t_expexp - 2*beta_expexp*tau*(tau-gam_expexp))

    ! tau**2 * alpha_tautau
    alpr(0,2) = dot_product(polTerms, t_pol*(t_pol-1)) + dot_product(expTerms, t_exp*(t_exp-1)) &
         + dot_product(expExpTerms, (t_expexp - 2*beta_expexp*tau*(tau-gam_expexp))**2 - t_expexp - 2*beta_expexp*tau**2 )

    ! delta*tau*alpha_deltatau
    alpr(1,1) = dot_product(polTerms, d_pol*t_pol) + dot_product(expTerms, (d_exp - l_exp*deltaL)*t_exp ) &
         + dot_product(expExpTerms, &
         (d_expexp - 2*eta_expexp*delta*(delta-eps_expexp))*(t_expexp - 2*beta_expexp*tau*(tau-gam_expexp)))

  end subroutine alphaResDerivs_PARA_H2

  function satDeltaEstimate_PARA_H2 (this,tau,phase) result(deltaSat)
    use thermopack_constants, only: LIQPH, VAPPH, SINGLEPH
    class(meos_para_h2) :: this
    real, intent(in) :: tau
    integer, intent(in) :: phase
    real :: deltaSat

    if ( phase == LIQPH .or. phase == SINGLEPH) then
       deltaSat = this%rhoLiq_triple/this%rc
    else if ( phase == VAPPH ) then
       deltaSat = this%rhoVap_triple/this%rc
    else
       call stoperror("satDeltaEstimate_ortho_h2: only LIQPH,VAPPH,SINGLEPH allowed!")
    end if

  end function satDeltaEstimate_PARA_H2

  subroutine assign_meos_para_h2(this,other)
    class(meos_para_h2), intent(inout) :: this
    class(*), intent(in) :: other
    !
    select type (other)
    class is (meos_para_h2)
      call this%assign_meos_base(other)

      this%tau_cache = other%tau_cache
      this%deltaSatLiq_cache = other%deltaSatLiq_cache
      this%deltaSatVap_cache = other%deltaSatVap_cache
      this%prefactors_pol_cache = other%prefactors_pol_cache
      this%prefactors_exp_cache = other%prefactors_exp_cache
      this%prefactors_expexp_cache = other%prefactors_expexp_cache

    class default
      call stoperror("assign_meos_para_h2: Should not be here....")
    end select
  end subroutine assign_meos_para_h2

end module multiparameter_PARA_H2
