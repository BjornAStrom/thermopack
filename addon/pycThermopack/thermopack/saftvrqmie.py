# Support for python2
from __future__ import print_function
# Import ctypes
from ctypes import *
# Importing Numpy (math, arrays, etc...)
import numpy as np
# Import platform to detect OS
from sys import platform, exit
# Import os utils
from os import path
# Import thermo
from . import thermo
# Import saftvrmie
from . import saftvrmie

c_len_type = thermo.c_len_type


class saftvrqmie(saftvrmie.saftvrmie):
    """
    Interface to SAFT-VRQ Mie
    """
    def __init__(self, comps=None, feynman_hibbs_order=1, parameter_reference="Default", minimum_temperature=None):
        """Initialize SAFT-VRQ Mie model in thermopack

        Equation of state and force fields for Feynman--Hibbs-corrected Mie fluids. I. Application to pure helium, neon, hydrogen, and deuterium
        (doi.org/10.1063/1.5111364
        Equation of state and force fields for Feynman–Hibbs-corrected Mie fluids. II. Application to mixtures of helium, neon, hydrogen, and deuterium
        (doi.org/10.1063/1.5136079)

        If no components are specified, model must be initialized for specific components later by direct call to 'init'
        Model can at any time be re-initialized for new components or parameters by direct calls to 'init'

        Args:
            comps (str, optional): Comma separated list of component names
            feynman_hibbs_order (int): Order of Feynman-Hibbs quantum corrections (1 or 2 supported). Defaults to 1.
            parameter_reference (str, optional): Which parameters to use?. Defaults to "Default".
            minimum_temperature (float, optional) : Is passed directly to thermopack::set_tmin()
        """
        # Load dll/so
        super(saftvrqmie, self).__init__()

        # Init methods
        self.s_eoslibinit_init_quantum_saftvrmie = getattr(self.tp, self.get_export_name("eoslibinit",
                                                                                         "init_quantum_saftvrmie"))
        # Quantum methods
        self.s_get_feynman_hibbs_order = getattr(
            self.tp, self.get_export_name("saftvrmie_containers",
                                          "get_feynman_hibbs_order"))
        self.lambda_a = np.zeros(self.nc)
        self.lambda_r = np.zeros(self.nc)
        if comps is not None:
            self.init(comps, feynman_hibbs_order=feynman_hibbs_order, parameter_reference=parameter_reference,
                      minimum_temperature=minimum_temperature)

    #################################
    # Init
    #################################

    def init(self, comps, feynman_hibbs_order=1, parameter_reference="Default", minimum_temperature=None):
        """Initialize SAFT-VRQ Mie model in thermopack

        Equation of state and force fields for Feynman--Hibbs-corrected Mie fluids. I. Application to pure helium, neon, hydrogen, and deuterium
        (doi.org/10.1063/1.5111364
        Equation of state and force fields for Feynman–Hibbs-corrected Mie fluids. II. Application to mixtures of helium, neon, hydrogen, and deuterium
        (doi.org/10.1063/1.5136079)

        Args:
            comps (str): Comma separated list of component names
            feynman_hibbs_order (int): Order of Feynman-Hibbs quantum corrections (1 or 2 supported). Defaults to 1.
            parameter_reference (str, optional): Which parameters to use?. Defaults to "Default".
            minimum_temperature (float, optional) : Is passed directly to thermopack::set_tmin()
        """
        self.activate()
        comp_string_c = c_char_p(comps.encode('ascii'))
        comp_string_len = c_len_type(len(comps))
        fh_c = c_int(feynman_hibbs_order)
        ref_string_c = c_char_p(parameter_reference.encode('ascii'))
        ref_string_len = c_len_type(len(parameter_reference))

        self.s_eoslibinit_init_quantum_saftvrmie.argtypes = [c_char_p,
                                                             POINTER(c_int),
                                                             c_char_p,
                                                             c_len_type,
                                                             c_len_type]

        self.s_eoslibinit_init_quantum_saftvrmie.restype = None

        self.s_eoslibinit_init_quantum_saftvrmie(comp_string_c,
                                                 byref(fh_c),
                                                 ref_string_c,
                                                 comp_string_len,
                                                 ref_string_len)
        self.nc = max(len(comps.split(" ")), len(comps.split(",")))
        self.set_tmin(minimum_temperature)

        # Map pure fluid parameters
        self.m = np.zeros(self.nc)
        self.sigma = np.zeros(self.nc)
        self.eps_div_kb = np.zeros(self.nc)
        self.lambda_a = np.zeros(self.nc)
        self.lambda_r = np.zeros(self.nc)
        for i in range(self.nc):
            self.m[i], self.sigma[i], self.eps_div_kb[i], self.lambda_a[i], self.lambda_r[i] = \
                self.get_pure_fluid_param(i+1)

    def get_feynman_hibbs_order(self, c):
        """Get Feynman-Hibbs order

        Args:
            c (int): Component index (FORTRAN)
        Returns:
           int: Feynman-Hibbs order
        """
        self.activate()
        c_c = c_int(c)
        fh_c = c_int(0)
        fh_hs_c = c_int(0)

        self.s_get_feynman_hibbs_order.argtypes = [POINTER(c_int),
                                                   POINTER(c_int),
                                                   POINTER(c_int)]

        self.s_get_feynman_hibbs_order.restype = None

        self.s_get_feynman_hibbs_order(byref(c_c),
                                       byref(fh_c),
                                       byref(fh_hs_c))
        return fh_c.value

    def print_saft_parameters(self, c):
        """Print saft parameters for component c

        Args:
            c (int): Component index (FORTRAN)

        """
        saftvrmie.saftvrmie.print_saft_parameters(self, c)
        fh = self.get_feynman_hibbs_order(c)
        print(f"FH order: {fh}")
