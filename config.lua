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
Config.ArriveDistance = 2.5        -- considered "arrived" when within this many meters
Config.NpcRunSpeed = 4.0           -- TaskGoToEntity speed (2.0 = walk, 3.0+ = jog/run)
Config.TreatTimeMs = 6000          -- how long doctor kneels / treats before revive
Config.DespawnAfterMs = 15000      -- delete NPC this long after revive
Config.EnrouteTimeoutMs = 90000    -- give up / teleport NPC to player if pathing takes longer
Config.AddBlip = true              -- blip on doctor so you can see him coming even if occluded
Config.Debug = true                -- F8 prints: model used, spawn coords, exists/visible checks

-- Doctor-dressed ped models (tried in order, first that loads is used)
Config.DoctorModels = {
    "u_m_m_valdoctor_01",
    "u_m_m_rhddoctor_01",
    "cs_sddoctor_01",
    "cs_creoledoctor",
}

-- Revive scenario played when doctor reaches player
-- WORLD_HUMAN_CROUCH_INSPECT is proven on RedM. Fallback: WORLD_HUMAN_KNEEL
Config.TreatScenario = "WORLD_HUMAN_CROUCH_INSPECT"
Config.TreatScenarioFallback = "WORLD_HUMAN_KNEEL"

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
