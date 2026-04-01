Config = Config or {}

-- Automatically apply drift when player enters driver seat
Config.ApplyOnEnter   = false

-- Fake "install" delay when enabling (ms)
Config.InstallMs      = 1200

-- Allowed vehicle classes (nil = all allowed)
-- 0-5 = compacts/sedans/SUV/coupes/muscle, 6-7 sports/super, 8 motorbikes, 9 offroad, 12 vans
Config.AllowedVehicleClasses = {0,1,2,3,4,5,6,7,8,9,12}

-- Keys / commands
Config.ToggleKey      = 'F5'
Config.MenuKey        = 'F6'
Config.ToggleCommand  = 'drift'
Config.MenuCommand    = 'driftmenu'

Config.Msg = {
    needDriver   = 'Sit in the driver seat first.',
    classBlocked = 'This vehicle class cannot use the drift chip.',
    installing   = 'Installing Drift Chip...',
    enabled      = '🔥 Drift Enabled',
    disabled     = '❌ Drift Disabled',
    autoEnabled  = '🔥 Drift Auto-Enabled',
    menuTitle    = 'WS Drift Modes',
}

-- =====================================================
-- Drift profiles using casup-style feel
-- =====================================================
-- mult[field] = multiplier on original handling float
-- clamp[field] = {min, max} to keep result sane
-- power = engine power multiplier (SetVehicleEnginePowerMultiplier)
-- torque = engine torque multiplier (SetVehicleEngineTorqueMultiplier)
-- tyres = not used yet but kept for future tyre mods
-- reduceGrip = makes car looser (we push loss multipliers a bit)

Config.Modes = {
    Balanced = {
        desc = "Street drift: stable, controllable slides.",
        mult = {
            fTractionCurveMin              = 0.90,
            fTractionCurveMax              = 0.92,
            fDriveInertia                  = 1.20,
            fInitialDriveForce             = 1.02,
            fClutchChangeRateScaleUpShift  = 3.4,
            fClutchChangeRateScaleDownShift= 3.4,
            fTractionLossMult              = 0.96,
        },
        clamp = {
            fTractionCurveMin     = {1.50, 2.20},
            fTractionCurveMax     = {1.80, 2.40},
            fTractionCurveLateral = {19.0, 24.0},

            fDriveInertia         = {0.90, 2.00},
            fInitialDriveForce    = {0.85, 1.60},

            fSteeringLock         = {42.0, 60.0},
            fTractionBiasFront    = {0.46, 0.52},
        },
        tyres      = true,
        reduceGrip = false,
        power      = 8.0,
        torque     = 1.05,
        smoke      = { r=255, g=255, b=255 },
    },

    Takeover = {
        desc = "Show mode: big angle, more smoke, looser rear.",
        mult = {
            fTractionCurveMin              = 0.84,
            fTractionCurveMax              = 0.88,
            fDriveInertia                  = 1.30,
            fInitialDriveForce             = 1.06,
            fClutchChangeRateScaleUpShift  = 4.0,
            fClutchChangeRateScaleDownShift= 4.0,
            fTractionLossMult              = 1.12,
        },
        clamp = {
            fTractionCurveMin     = {1.40, 2.10},
            fTractionCurveMax     = {1.70, 2.30},
            fTractionCurveLateral = {19.0, 23.0},

            fDriveInertia         = {1.00, 2.20},
            fInitialDriveForce    = {0.90, 1.80},

            fSteeringLock         = {48.0, 66.0},
            fTractionBiasFront    = {0.45, 0.51},
        },
        tyres      = true,
        reduceGrip = true,
        power      = 12.0,
        torque     = 1.08,
        smoke      = { r=255, g=255, b=180 },
        sound      = 'car_horn',
    },

    Pursuit = {
        desc = "Hybrid grip+drift for chase driving.",
        mult = {
            fTractionCurveMin              = 0.96,
            fTractionCurveMax              = 0.98,
            fDriveInertia                  = 1.15,
            fInitialDriveForce             = 1.08,
            fClutchChangeRateScaleUpShift  = 3.8,
            fClutchChangeRateScaleDownShift= 3.8,
            fTractionLossMult              = 0.92,
        },
        clamp = {
            fTractionCurveMin     = {1.70, 2.30},
            fTractionCurveMax     = {2.00, 2.50},
            fTractionCurveLateral = {20.0, 25.0},

            fDriveInertia         = {0.90, 2.00},
            fInitialDriveForce    = {0.90, 1.80},

            fSteeringLock         = {40.0, 58.0},
            fTractionBiasFront    = {0.47, 0.53},
        },
        tyres      = true,
        reduceGrip = false,
        power      = 10.0,
        torque     = 1.06,
        smoke      = { r=180, g=220, b=255 },
    },

    JDM = {
        desc = "Snappy throttle, precise angle.",
        mult = {
            fTractionCurveMin              = 0.88,
            fTractionCurveMax              = 0.90,
            fDriveInertia                  = 1.28,
            fInitialDriveForce             = 1.05,
            fClutchChangeRateScaleUpShift  = 4.5,
            fClutchChangeRateScaleDownShift= 4.5,
            fTractionLossMult              = 1.02,
        },
        clamp = {
            fTractionCurveMin  = {1.55, 2.15},
            fTractionCurveMax  = {1.85, 2.45},
            fSteeringLock      = {44.0, 62.0},
            fInitialDriveForce = {0.90, 1.75},
        },
        tyres      = true,
        reduceGrip = false,
        power      = 10.0,
        torque     = 1.06,
        smoke      = { r=180, g=255, b=180 },
    },

    Muscle = {
        desc = "Big torque, long loud slides.",
        mult = {
            fTractionCurveMin              = 0.86,
            fTractionCurveMax              = 0.88,
            fDriveInertia                  = 1.32,
            fInitialDriveForce             = 1.10,
            fClutchChangeRateScaleUpShift  = 3.8,
            fClutchChangeRateScaleDownShift= 3.8,
            fTractionLossMult              = 1.08,
        },
        clamp = {
            fTractionCurveMin  = {1.45, 2.05},
            fTractionCurveMax  = {1.75, 2.35},
            fSteeringLock      = {46.0, 64.0},
            fInitialDriveForce = {0.90, 1.90},
        },
        tyres      = true,
        reduceGrip = false,
        power      = 14.0,
        torque     = 1.10,
        smoke      = { r=255, g=180, b=180 },
    },
}
