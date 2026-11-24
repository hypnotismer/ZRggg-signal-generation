import FWCore.ParameterSet.Config as cms

# Summer24 (13.6 TeV). The wrapper fills the gridpack path and Pythia mass.
externalLHEProducer = cms.EDProducer(
    "ExternalLHEProducer",
    args=cms.vstring('/eos/cms/store/group/phys_exotica/Boosted_X_to_3gluons/gridpacks/run3/WZR_012j_NLO_WToLNu_M__ZR_MASS___el9_amd64_gcc11_CMSSW_13_2_9_tarball.tar.xz'),
    nEvents=cms.untracked.uint32(5000),
    numberOfParameters=cms.uint32(1),
    generateConcurrently=cms.untracked.bool(False),
    outputFile=cms.string("cmsgrid_final.lhe"),
    scriptName=cms.FileInPath("GeneratorInterface/LHEInterface/data/run_generic_tarball_cvmfs.sh"),
)

from Configuration.Generator.Pythia8CommonSettings_cfi import *
from Configuration.Generator.MCTunesRun3ECM13p6TeV.PythiaCP5Settings_cfi import *
from Configuration.Generator.PSweightsPythia.PythiaPSweightsSettings_cfi import *
from Configuration.Generator.Pythia8aMCatNLOSettings_cfi import *

generator = cms.EDFilter(
    "Pythia8ConcurrentHadronizerFilter",
    maxEventsToPrint=cms.untracked.int32(1),
    pythiaPylistVerbosity=cms.untracked.int32(1),
    filterEfficiency=cms.untracked.double(1.0),
    pythiaHepMCVerbosity=cms.untracked.bool(True),
    comEnergy=cms.double(13600.0),
    PythiaParameters=cms.PSet(
        pythia8CommonSettingsBlock,
        pythia8CP5SettingsBlock,
        pythia8PSweightsSettingsBlock,
        pythia8aMCatNLOSettingsBlock,
        processParameters=cms.vstring(
            # FxFx merging for WZR + 0,1,2 production jets at NLO.
            "JetMatching:setMad = off",
            "JetMatching:merge = on",
            "JetMatching:coneRadius = 1.0",
            "JetMatching:etaJetMax = 999.",
            "JetMatching:qCut = 30.",
            "JetMatching:doFxFx = on",
            "JetMatching:nJetMax = 2",
            "32:m0 = __ZR_MASS__",
            "32:isResonance = on",
            "32:mayDecay = on",
            "32:onMode = off",
            "32:oneChannel = 1 1.0 102 21 21 21",
        ),
        parameterSets=cms.vstring(
            "pythia8CommonSettings", "pythia8CP5Settings",
            "pythia8PSweightsSettings", "pythia8aMCatNLOSettings",
            "processParameters",
        ),
    ),
)
