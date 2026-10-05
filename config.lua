Config = {}

-- Key to HOLD to call medic (W / MOVE UP)
-- 0x8FD015D8 = INPUT_MOVE_UP_ONLY (W)
Config.HoldKey = 0x8FD015D8
Config.HoldKeyLabel = "W"

-- How long (ms) player must HOLD W to trigger medic call
Config.HoldTimeMs = 2000

-- Medic spawn / behaviour
-- NOTE: 45m+ is often behind hills/trees/buildings and looks "invisible".
-- 25-30m keeps the NPC in view while still feeling like he "comes from town".
Config.SpawnDistance = 28.0        -- approx distance from player to spawn NPC doctor
Config.SpawnDistanceVariance = 8.0 -- +/- random variance
Config.ArriveDistance = 1.4        -- considered "arrived" when within this many meters (kneel-close)
Config.TreatOffset = 1.2           -- final placement: medic stands this many meters from body
Config.NpcRunSpeed = 4.0           -- TaskGoToEntity speed (2.0 = walk, 3.0+ = jog/run)
Config.TreatTimeMs = 6000          -- how long doctor kneels / treats before revive
Config.DespawnAfterMs = 15000      -- delete NPC this long after revive
Config.EnrouteTimeoutMs = 90000    -- give up / teleport NPC to player if pathing takes longer
Config.AddBlip = true              -- blip on doctor so you can see him coming even if occluded
Config.Debug = true                -- F8 prints: model used, spawn coords, exists/visible checks

-- Death cam: elevated wide view so the approaching medic stays in frame.
-- Like RDR2 AFK cam: cycles angles every CycleMs while dead.
Config.DeathCam = {
    Enabled = true,
    Height = 7.0,        -- cam height above player
    Distance = 12.0,     -- cam distance from player
    Fov = 65.0,          -- wider than gameplay (~50) so medic stays in frame
    CycleMs = 7000,      -- switch angle every 7s (multi-angle cinematic)
    TrackMedic = true,   -- when medic enroute: frame player+medic instead of pure orbit
}

-- Doctor-dressed ped models (tried in order, first that loads is used)
Config.DoctorModels = {
    "u_m_m_valdoctor_01",
    "u_m_m_rhddoctor_01",
    "cs_sddoctor_01",
    "cs_creoledoctor",
}

-- Revive treatment: real RDO medical interaction (scenario system disabled).
-- Case-study sources (RedM-AI-Knowledge-Brain):
--   mech_revive@mp@crouched|normal|action = revive_l_front/_left/_r_front/_r_right (MP revive set)
--   mech_revive@unapproved = syringe_revive, revive (SP fallback)
--   script_common@other@unapproved = medic_kneel_enter, medic_kneel_base
--   anim_events = joaat("give_meds") / joaat("med_or_suck") are EVENTS, not dicts
--   RDRO_DV_Sounds = { "Revive" }
Config.TreatScenario = nil
Config.TreatScenarioFallback = nil
Config.TreatAnim = nil -- legacy single-anim slot, superseded below

Config.TreatKneel = {
    dict = "script_common@other@unapproved",
    enter = "medic_kneel_enter",
    base = "medic_kneel_base",
}

Config.TreatRevive = {
    dict = "mech_revive@mp@crouched", -- crouched fits the 1.2m kneel-close
    clips = { "revive_l_front", "revive_l_left", "revive_r_front", "revive_r_right" },
    event = "give_meds",              -- anim event to listen for via HasAnimEventFired
    fallbackDict = "mech_revive@unapproved",
    fallbackClip = "revive",
}

Config.TreatSound = {
    set = "RDRO_DV_Sounds",
    sound = "Revive",
}

-- Revive
Config.ReviveFee = 0.0 -- set > 0 to charge via vorp_core (0 = free)

-- If true, server checks for online doctors with job "doctor" and blocks NPC if any online.
-- Requires vorp_core. Set false to always allow NPC medic.
Config.OnlyWhenNoDoctorsOnline = false
Config.DoctorJobName = "doctor"

-- UI text
Config.Texts = {
    holdPrompt      = "HOLD ~o~[%s]~q~ TO CALL MEDIC",
    holding         = "CALLING MEDIC... %d%%",
    medicComing     = "MEDIC IS COMING",
    medicDistance   = "%dm",
    medicArrived    = "DOCTOR IS TREATING YOU...",
    revived         = "You have been revived.",
    alreadyCalled   = "Medic has already been called - he is on the way!",
    doctorsOnline   = "Doctors are online - NPC medic unavailable.",
    feePaid         = "You paid $%s for medical services.",
}
