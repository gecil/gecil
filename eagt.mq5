//+------------------------------------------------------------------+
//|                                           GT_Recovery_Engine.mq5 |
//|                     GT Recovery Engine - Institutional MT5 EA    |
//|     Probability-Driven Recovery (Martingale Klasik vs Flip)      |
//|             Powered by ICT_SMC_CRT + ICT/SMC/CRT Structure       |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, GT Recovery Engine"
#property version     "1.33"
#property description "GT Recovery Engine (All-in-One): ICT+SMC+CRT Entry + Direct Flip Martingale (Buy SL->Sell, Sell SL->Buy Sampai TP)"
#property description "v1.33: SL/TP Flip mewarisi jarak SL entry awal (presisi RR) + Re-Anchor via Deal ID + Alasan Entry di komentar order & kode"
#property strict

#include <Trade\Trade.mqh>

//--- Chart object prefix
#define GT_OBJ_PREFIX "GTRE_"

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_GT_SIGNAL_SOURCE
{
   GT_SRC_INTERNAL_ALL_IN_ONE = 0, // All-in-One Internal ICT+SMC+CRT (1 File EA)
   GT_SRC_EXTERNAL_ICUSTOM    = 1  // Indikator Eksternal ICT_SMC_CRT (iCustom)
};

enum ENUM_GT_ENTRY_SENSITIVITY
{
   GT_SENS_CONSERVATIVE = 0,       // Konservatif (Konfluensi Ketat)
   GT_SENS_BALANCED     = 1,       // Seimbang (Rekomendasi)
   GT_SENS_AGGRESSIVE   = 2        // Agresif (Frekuensi Sinyal Tinggi)
};

enum ENUM_GT_BIAS
{
   GT_BIAS_BEARISH = -1,
   GT_BIAS_NEUTRAL =  0,
   GT_BIAS_BULLISH =  1
};

enum ENUM_GT_ASSET_CLASS
{
   GT_ASSET_AUTO     = 0,  // Auto Detect (Forex/XAUUSD/Index/CFD)
   GT_ASSET_FOREX    = 1,  // Forex (4/5 digit & JPY 2/3 digit)
   GT_ASSET_GOLD     = 2,  // Metals / XAUUSD (1 pip = 0.10)
   GT_ASSET_SILVER   = 3,  // Metals / XAGUSD (1 pip = 0.01)
   GT_ASSET_INDEX    = 4,  // Indices (1 pip = 1.00)
   GT_ASSET_CRYPTO   = 5,  // Crypto (Auto scaled)
   GT_ASSET_CFD      = 6,  // Commodities / Stock CFDs
   GT_ASSET_CUSTOM   = 7   // Custom Pip Size
};

enum ENUM_GT_SLTP_MODE
{
   GT_SLTP_INDICATOR   = 0, // SL/TP Indikator (Buffer ICT_SMC_CRT)
   GT_SLTP_FIXED_PIP   = 1, // Fixed Pip (SL & TP tetap)
   GT_SLTP_RISK_REWARD = 2  // Risk Reward (TP = SL x RR)
};

enum ENUM_GT_RR_MODE
{
   GT_RR_1_1    = 0,        // RR 1:1
   GT_RR_1_2    = 1,        // RR 1:2
   GT_RR_1_3    = 2,        // RR 1:3
   GT_RR_CUSTOM = 3         // Custom RR
};

enum ENUM_GT_GRID_STEP
{
   GT_GRID_10_PIP = 0,      // 10 Pip
   GT_GRID_20_PIP = 1,      // 20 Pip
   GT_GRID_30_PIP = 2,      // 30 Pip
   GT_GRID_CUSTOM = 3       // Custom Pip
};

enum ENUM_GT_LOT_MULT
{
   GT_MULT_1_2    = 0,      // 1.2x
   GT_MULT_1_3    = 1,      // 1.3x
   GT_MULT_1_5    = 2,      // 1.5x
   GT_MULT_2_0    = 3,      // 2.0x
   GT_MULT_CUSTOM = 4       // Custom Multiplier
};

enum ENUM_GT_LOSS_MODE
{
   GT_LOSS_CURRENCY = 0,    // Mata Uang Akun (USD/Deposit Currency)
   GT_LOSS_PERCENT  = 1     // Persentase Balance (%)
};

enum ENUM_GT_RECOVERY_MODE
{
   GT_REC_NONE    = 0,      // Standby (Belum Ada Recovery)
   GT_REC_CLASSIC = 1,      // Martingale Klasik (Struktur Utuh)
   GT_REC_FLIP    = 2       // Flip Martingale (Balik Arah Recovery)
};

enum ENUM_GT_FLIP_EXEC_MODE
{
   GT_FLIP_DIRECT_ON_SL = 0, // Direct Flip Saat SL (Buy SL->Sell, Sell SL->Buy Sampai TP)
   GT_FLIP_HYBRID_LOCK  = 1, // Hybrid (Probabilitas Awal -> Begitu Flip Aktif Langsung Balik Saat SL)
   GT_FLIP_PROB_GATED   = 2  // Probability-Gated (Setiap Recovery Cek Skor Probabilitas ICT/SMC/CRT)
};

enum ENUM_GT_FLIP_TIER
{
   GT_TIER_NONE = 0,        // Tidak Ada Sinyal Flip
   GT_TIER_3    = 3,        // Tier 3 (Sedang: BOS / iBOS / iCHoCH)
   GT_TIER_2    = 2,        // Tier 2 (Kuat: xSSL/xBSL + CHoCH / IFVG)
   GT_TIER_1    = 1         // Tier 1 (Sangat Kuat: IDM Sweep / xSSL / xBSL / CHoCH / CRT Reverse)
};

enum ENUM_GT_DIR
{
   GT_DIR_NONE =  0,
   GT_DIR_BUY  =  1,
   GT_DIR_SELL = -1
};

enum ENUM_GT_CLASSIC_TP_MODE
{
   GT_CLASSIC_TP_BASKET     = 0, // Basket Recovery TP (Rata-rata + TP)
   GT_CLASSIC_TP_INDIVIDUAL = 1  // Individual TP per Posisi
};

//+------------------------------------------------------------------+
//| Indicator Signal Snapshot (Buffers 0..6 of ICT_SMC_CRT)          |
//+------------------------------------------------------------------+
struct SIndicatorData
{
   bool         valid;
   datetime     barTime;
   double       buySignalRaw;
   double       sellSignalRaw;
   bool         buySignal;
   bool         sellSignal;
   double       buySL;
   double       buyTP;
   double       sellSL;
   double       sellTP;
   ENUM_GT_BIAS bias;
   ENUM_GT_BIAS prevBias;
   bool         biasChangedToBull;
   bool         biasChangedToBear;
   string       signalReason;

   void Reset()
   {
      valid             = false;
      barTime           = 0;
      buySignalRaw      = 0.0;
      sellSignalRaw     = 0.0;
      buySignal         = false;
      sellSignal        = false;
      buySL             = 0.0;
      buyTP             = 0.0;
      sellSL            = 0.0;
      sellTP            = 0.0;
      bias              = GT_BIAS_NEUTRAL;
      prevBias          = GT_BIAS_NEUTRAL;
      biasChangedToBull = false;
      biasChangedToBear = false;
      signalReason      = "-";
   }
};

//+------------------------------------------------------------------+
//| ICT + SMC + CRT Market Structure & Probability Context           |
//+------------------------------------------------------------------+
struct SMarketContext
{
   datetime barTime;
   double   closePrice;
   double   highPrice;
   double   lowPrice;

   int      extTrend;
   double   lastExtHigh;
   double   lastExtLow;
   bool     bosBull;
   bool     bosBear;
   bool     chochBull;
   bool     chochBear;

   int      intTrend;
   double   lastIntHigh;
   double   lastIntLow;
   bool     ibosBull;
   bool     ibosBear;
   bool     ichochBull;
   bool     ichochBear;

   double   idmHighLevel;
   double   idmLowLevel;
   bool     idmSweptBull;
   bool     idmSweptBear;
   bool     sweepBull;
   bool     sweepBear;
   bool     xSSL;
   bool     xBSL;
   bool     eqhDetected;
   bool     eqlDetected;
   bool     eqhSweptBear;
   bool     eqlSweptBull;

   bool     bullOBValid;
   double   bullOBHigh;
   double   bullOBLow;
   bool     bearOBValid;
   double   bearOBHigh;
   double   bearOBLow;
   bool     atBullOB;
   bool     atBearOB;

   bool     bullBreakerActive;
   bool     bearBreakerActive;

   bool     bullFVGValid;
   double   bullFVGHigh;
   double   bullFVGLow;
   bool     bearFVGValid;
   double   bearFVGHigh;
   double   bearFVGLow;

   bool     bullIFVG;
   bool     bearIFVG;

   bool     bullMB;
   bool     bearMB;

   bool     bullVI;
   bool     bearVI;

   bool     bullVoid;
   bool     bearVoid;

   double   rangeHigh;
   double   rangeLow;
   double   eq50;
   bool     inPremium;
   bool     inDiscount;
   bool     inBullOTE;
   bool     inBearOTE;

   double   pdh;
   double   pdl;
   double   pwh;
   double   pwl;
   bool     pdhSweptBear;
   bool     pdlSweptBull;
   bool     pwhSweptBear;
   bool     pwlSweptBull;

   double   crtRefHigh;
   double   crtRefLow;
   bool     crtBull;
   bool     crtBear;

   bool     inKillZone;
   string   killZoneName;

   void Reset()
   {
      barTime           = 0;
      closePrice        = 0.0;
      highPrice         = 0.0;
      lowPrice          = 0.0;
      extTrend          = 0;
      lastExtHigh       = 0.0;
      lastExtLow        = 0.0;
      bosBull           = false;
      bosBear           = false;
      chochBull         = false;
      chochBear         = false;
      intTrend          = 0;
      lastIntHigh       = 0.0;
      lastIntLow        = 0.0;
      ibosBull          = false;
      ibosBear          = false;
      ichochBull        = false;
      ichochBear        = false;
      idmHighLevel      = 0.0;
      idmLowLevel       = 0.0;
      idmSweptBull      = false;
      idmSweptBear      = false;
      sweepBull         = false;
      sweepBear         = false;
      xSSL              = false;
      xBSL              = false;
      eqhDetected       = false;
      eqlDetected       = false;
      eqhSweptBear      = false;
      eqlSweptBull      = false;
      bullOBValid       = false;
      bullOBHigh        = 0.0;
      bullOBLow         = 0.0;
      bearOBValid       = false;
      bearOBHigh        = 0.0;
      bearOBLow         = 0.0;
      atBullOB          = false;
      atBearOB          = false;
      bullBreakerActive = false;
      bearBreakerActive = false;
      bullFVGValid      = false;
      bullFVGHigh       = 0.0;
      bullFVGLow        = 0.0;
      bearFVGValid      = false;
      bearFVGHigh       = 0.0;
      bearFVGLow        = 0.0;
      bullIFVG          = false;
      bearIFVG          = false;
      bullMB            = false;
      bearMB            = false;
      bullVI            = false;
      bearVI            = false;
      bullVoid          = false;
      bearVoid          = false;
      rangeHigh         = 0.0;
      rangeLow          = 0.0;
      eq50              = 0.0;
      inPremium         = false;
      inDiscount        = false;
      inBullOTE         = false;
      inBearOTE         = false;
      pdh               = 0.0;
      pdl               = 0.0;
      pwh               = 0.0;
      pwl               = 0.0;
      pdhSweptBear      = false;
      pdlSweptBull      = false;
      pwhSweptBear      = false;
      pwlSweptBull      = false;
      crtRefHigh        = 0.0;
      crtRefLow         = 0.0;
      crtBull           = false;
      crtBear           = false;
      inKillZone        = false;
      killZoneName      = "OFF";
   }
};

//+------------------------------------------------------------------+
//| Probability Weights Configuration                                |
//+------------------------------------------------------------------+
struct SScoreWeights
{
   bool   enabled;
   int    flipThreshold;
   int    wIDM;
   int    wXSSL;
   int    wXBSL;
   int    wCHoCH;
   int    wCRT;
   int    wIFVG;
   int    wFVG;
   int    wOB;
   int    wBOS;
   int    wICHoCH;
   int    wIBOS;
   int    wOTE;
   int    wDiscount;
   int    wPremium;
   int    wSweep;
   int    wEQH_EQL;
   int    wBreaker;
   int    wMB_VI_Void;
   int    wHTFLiq;
   int    wKillZone;
   int    wIndBiasFlip;
   bool   requireIntactStructureForClassic;
};

//+------------------------------------------------------------------+
//| Probability Evaluation Result                                    |
//+------------------------------------------------------------------+
struct SProbabilityDecision
{
   ENUM_GT_RECOVERY_MODE mode;
   ENUM_GT_FLIP_TIER     highestTier;
   ENUM_GT_DIR           evaluatedForDir;
   ENUM_GT_DIR           recommendedDir;
   int                   reversalScore;
   int                   continuationScore;
   int                   threshold;
   bool                  structureIntact;
   bool                  allowExecution;
   int                   tier1Count;
   int                   tier2Count;
   int                   tier3Count;
   string                activeReversalFactors;
   string                activeContinuationFactors;
   string                summaryReason;

   void Reset()
   {
      mode                      = GT_REC_NONE;
      highestTier               = GT_TIER_NONE;
      evaluatedForDir           = GT_DIR_NONE;
      recommendedDir            = GT_DIR_NONE;
      reversalScore             = 0;
      continuationScore         = 0;
      threshold                 = 0;
      structureIntact           = true;
      allowExecution            = false;
      tier1Count                = 0;
      tier2Count                = 0;
      tier3Count                = 0;
      activeReversalFactors     = "-";
      activeContinuationFactors = "-";
      summaryReason             = "Standby";
   }
};

//+------------------------------------------------------------------+
//| Validation Result                                                |
//+------------------------------------------------------------------+
struct SValidationResult
{
   bool   isValid;
   bool   hasWarning;
   string errorMessage;
   string warningMessage;

   void Reset()
   {
      isValid        = true;
      hasWarning     = false;
      errorMessage   = "";
      warningMessage = "";
   }
};

//+------------------------------------------------------------------+
//| Recovery Simulator Metrics                                       |
//+------------------------------------------------------------------+
struct SSimulatorMetrics
{
   double balance;
   double equity;
   double initialLot;
   double multiplier;
   int    maxLevel;
   double gridStepPips;
   double slPips;
   double tpPips;
   double rrRatio;
   double totalExposureLots;
   double maxSingleLevelLot;
   double estClassicDrawdownMoney;
   double estClassicDrawdownPct;
   double estFlipDrawdownMoney;
   double estFlipDrawdownPct;
   double targetRecoveryMoney;
   double targetRecoveryPips;
   double pipValuePerLot;

   void Reset()
   {
      balance                 = 0.0;
      equity                  = 0.0;
      initialLot              = 0.0;
      multiplier              = 1.0;
      maxLevel                = 0;
      gridStepPips            = 0.0;
      slPips                  = 0.0;
      tpPips                  = 0.0;
      rrRatio                 = 1.0;
      totalExposureLots       = 0.0;
      maxSingleLevelLot       = 0.0;
      estClassicDrawdownMoney = 0.0;
      estClassicDrawdownPct   = 0.0;
      estFlipDrawdownMoney    = 0.0;
      estFlipDrawdownPct      = 0.0;
      targetRecoveryMoney     = 0.0;
      targetRecoveryPips      = 0.0;
      pipValuePerLot          = 0.0;
   }
};

//+------------------------------------------------------------------+
//| Safety Status                                                    |
//+------------------------------------------------------------------+
struct SSafetyStatus
{
   bool   tradingHalted;
   bool   emergencyActive;
   bool   maxLevelReached;
   bool   maxFloatingLossHit;
   bool   maxDailyDDHit;
   bool   maxPositionsHit;
   double dayStartBalance;
   double currentDailyDDPct;
   double currentFloatingPL;
   int    currentOpenPositions;
   string haltReason;

   void Reset()
   {
      tradingHalted        = false;
      emergencyActive      = false;
      maxLevelReached      = false;
      maxFloatingLossHit   = false;
      maxDailyDDHit        = false;
      maxPositionsHit      = false;
      dayStartBalance      = 0.0;
      currentDailyDDPct    = 0.0;
      currentFloatingPL    = 0.0;
      currentOpenPositions = 0;
      haltReason           = "SAFE";
   }
};

//+------------------------------------------------------------------+
//| Active Recovery Cycle State                                      |
//+------------------------------------------------------------------+
struct SRecoveryState
{
   bool                  cycleActive;
   bool                  flipCycleLocked;
   ENUM_GT_DIR           currentDir;
   int                   currentLevel;
   ENUM_GT_RECOVERY_MODE lastMode;
   double                lastEntryPrice;
   double                lastLot;
   double                realizedCyclePL;
   datetime              lastActionBarTime;
   bool                  pendingPostSLReEval;
   ENUM_GT_DIR           lastLostDir;
   double                lastLostPrice;
   int                   classicCount;
   int                   flipCount;

   //--- [v1.33] Jarak SL/TP (dalam harga) dari entry awal siklus -> dipakai ulang oleh semua Flip
   double                cycleSLDistPx;
   double                cycleTPDistPx;
   //--- [v1.33] Alasan entry terakhir (untuk log / panel)
   string                lastEntryReason;

   void Reset()
   {
      cycleActive         = false;
      flipCycleLocked     = false;
      currentDir          = GT_DIR_NONE;
      currentLevel        = 0;
      lastMode            = GT_REC_NONE;
      lastEntryPrice      = 0.0;
      lastLot             = 0.0;
      realizedCyclePL     = 0.0;
      lastActionBarTime   = 0;
      pendingPostSLReEval = false;
      lastLostDir         = GT_DIR_NONE;
      lastLostPrice       = 0.0;
      classicCount        = 0;
      flipCount           = 0;
      cycleSLDistPx       = 0.0;
      cycleTPDistPx       = 0.0;
      lastEntryReason     = "-";
   }
};

//+------------------------------------------------------------------+
//| Helper functions for enum string labels                          |
//+------------------------------------------------------------------+
string GT_BiasToString(const ENUM_GT_BIAS bias)
{
   if(bias == GT_BIAS_BULLISH) return "BULLISH (+1)";
   if(bias == GT_BIAS_BEARISH) return "BEARISH (-1)";
   return "NETRAL (0)";
}

string GT_DirToString(const ENUM_GT_DIR dir)
{
   if(dir == GT_DIR_BUY)  return "BUY";
   if(dir == GT_DIR_SELL) return "SELL";
   return "NONE";
}

string GT_RecoveryModeToString(const ENUM_GT_RECOVERY_MODE mode)
{
   if(mode == GT_REC_CLASSIC) return "MARTINGALE KLASIK";
   if(mode == GT_REC_FLIP)    return "FLIP MARTINGALE";
   return "STANDBY";
}

string GT_TierToString(const ENUM_GT_FLIP_TIER tier)
{
   if(tier == GT_TIER_1) return "TIER 1 (Sangat Kuat)";
   if(tier == GT_TIER_2) return "TIER 2 (Kuat)";
   if(tier == GT_TIER_3) return "TIER 3 (Sedang)";
   return "NONE";
}

double GT_ResolveGridStepPips(const ENUM_GT_GRID_STEP mode, const double customPips)
{
   switch(mode)
   {
      case GT_GRID_10_PIP: return 10.0;
      case GT_GRID_20_PIP: return 20.0;
      case GT_GRID_30_PIP: return 30.0;
      case GT_GRID_CUSTOM: return customPips;
   }
   return 20.0;
}

double GT_ResolveMultiplier(const ENUM_GT_LOT_MULT mode, const double customMult)
{
   switch(mode)
   {
      case GT_MULT_1_2:    return 1.2;
      case GT_MULT_1_3:    return 1.3;
      case GT_MULT_1_5:    return 1.5;
      case GT_MULT_2_0:    return 2.0;
      case GT_MULT_CUSTOM: return customMult;
   }
   return 1.5;
}

double GT_ResolveRR(const ENUM_GT_RR_MODE mode, const double customRR)
{
   switch(mode)
   {
      case GT_RR_1_1:    return 1.0;
      case GT_RR_1_2:    return 2.0;
      case GT_RR_1_3:    return 3.0;
      case GT_RR_CUSTOM: return customRR;
   }
   return 2.0;
}

//+------------------------------------------------------------------+
//| CPipConverter: Automatic digit & instrument pip standardization  |
//+------------------------------------------------------------------+
class CPipConverter
{
private:
   string              m_symbol;
   int                 m_digits;
   double              m_point;
   double              m_pipSize;
   double              m_pointsPerPip;
   ENUM_GT_ASSET_CLASS m_detectedClass;
   ENUM_GT_ASSET_CLASS m_requestedClass;
   double              m_customPipSize;

   bool ContainsAny(const string text, const string &patterns[]) const
   {
      int n = ArraySize(patterns);
      for(int i = 0; i < n; i++)
      {
         if(StringFind(text, patterns[i]) >= 0)
            return true;
      }
      return false;
   }

   ENUM_GT_ASSET_CLASS DetectAssetClass(const string symUpper) const
   {
      string goldPatterns[] = {"XAU", "GOLD"};
      if(ContainsAny(symUpper, goldPatterns))
         return GT_ASSET_GOLD;

      string silverPatterns[] = {"XAG", "SILVER"};
      if(ContainsAny(symUpper, silverPatterns))
         return GT_ASSET_SILVER;

      string idxPatterns[] = {
         "US30", "DJ30", "DJI", "WS30", "DOW",
         "NAS100", "USTEC", "US100", "NDX", "NQ",
         "US500", "SPX", "SP500", "ES",
         "GER40", "GER30", "DE40", "DE30", "DAX",
         "UK100", "FTSE", "JP225", "JPN225", "NI225", "NIKKEI",
         "HK50", "HSI", "FRA40", "CAC40", "AUS200", "EU50", "STOXX", "US2000", "RUS2000"
      };
      if(ContainsAny(symUpper, idxPatterns))
         return GT_ASSET_INDEX;

      string cryptoPatterns[] = {"BTC", "ETH", "SOL", "BNB", "XRP", "LTC", "ADA", "DOGE", "AVAX"};
      if(ContainsAny(symUpper, cryptoPatterns))
         return GT_ASSET_CRYPTO;

      string oilPatterns[] = {"USOIL", "UKOIL", "WTI", "BRENT", "XTI", "XBR", "NGAS", "CRUDE", "OIL"};
      if(ContainsAny(symUpper, oilPatterns))
         return GT_ASSET_CFD;

      long calcMode = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_CALC_MODE);
      if(calcMode == SYMBOL_CALC_MODE_FOREX || calcMode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)
         return GT_ASSET_FOREX;

      if(calcMode == SYMBOL_CALC_MODE_CFDINDEX)
         return GT_ASSET_INDEX;

      if(calcMode == SYMBOL_CALC_MODE_CFD ||
         calcMode == SYMBOL_CALC_MODE_CFDLEVERAGE ||
         calcMode == SYMBOL_CALC_MODE_EXCH_STOCKS ||
         calcMode == SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX)
         return GT_ASSET_CFD;

      string fxCurrencies[] = {"EUR", "USD", "GBP", "JPY", "CHF", "AUD", "NZD", "CAD"};
      int hits = 0;
      for(int i = 0; i < ArraySize(fxCurrencies); i++)
      {
         if(StringFind(symUpper, fxCurrencies[i]) >= 0)
            hits++;
      }
      if(hits >= 2)
         return GT_ASSET_FOREX;

      return GT_ASSET_CFD;
   }

   double ResolvePipSize(const ENUM_GT_ASSET_CLASS cls, const string symUpper) const
   {
      if(cls == GT_ASSET_CUSTOM && m_customPipSize > 0.0)
         return m_customPipSize;

      switch(cls)
      {
         case GT_ASSET_FOREX:
         {
            if(StringFind(symUpper, "JPY") >= 0)
               return 0.01;
            if(m_digits == 5 || m_digits == 4)
               return 0.0001;
            if(m_digits == 3 || m_digits == 2)
               return 0.01;
            return (m_digits > 0) ? m_point * 10.0 : m_point;
         }

         case GT_ASSET_GOLD:
            return 0.10;

         case GT_ASSET_SILVER:
            return 0.01;

         case GT_ASSET_INDEX:
            return 1.0;

         case GT_ASSET_CRYPTO:
         {
            double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            if(price >= 1000.0) return 1.0;
            if(price >= 10.0)   return 0.10;
            if(price >= 1.0)    return 0.01;
            return (m_digits >= 4) ? 0.0001 : m_point * 10.0;
         }

         case GT_ASSET_CFD:
         default:
         {
            if(m_digits == 3) return 0.01;
            if(m_digits == 2) return 0.01;
            if(m_digits == 1) return 0.1;
            if(m_digits == 0) return 1.0;
            if(m_digits >= 4) return 0.0001;
            return m_point;
         }
      }
   }

public:
   CPipConverter()
   {
      m_symbol         = _Symbol;
      m_digits         = 0;
      m_point          = 0.0001;
      m_pipSize        = 0.0001;
      m_pointsPerPip   = 1.0;
      m_detectedClass  = GT_ASSET_FOREX;
      m_requestedClass = GT_ASSET_AUTO;
      m_customPipSize  = 0.0;
   }

   bool Init(const string symbol,
             const ENUM_GT_ASSET_CLASS assetMode = GT_ASSET_AUTO,
             const double customPipSize = 0.0)
   {
      m_symbol         = symbol;
      m_requestedClass = assetMode;
      m_customPipSize  = customPipSize;

      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(m_point <= 0.0)
         return false;

      string symUpper = m_symbol;
      StringToUpper(symUpper);

      if(assetMode == GT_ASSET_AUTO)
         m_detectedClass = DetectAssetClass(symUpper);
      else
         m_detectedClass = assetMode;

      m_pipSize = ResolvePipSize(m_detectedClass, symUpper);
      if(m_pipSize < m_point)
         m_pipSize = m_point;

      m_pointsPerPip = m_pipSize / m_point;
      return true;
   }

   string              SymbolName()    const { return m_symbol; }
   int                 Digits()        const { return m_digits; }
   double              PointSize()     const { return m_point; }
   double              PipSize()       const { return m_pipSize; }
   double              PointsPerPip()  const { return m_pointsPerPip; }
   ENUM_GT_ASSET_CLASS AssetClass()    const { return m_detectedClass; }

   string GetAssetClassName() const
   {
      switch(m_detectedClass)
      {
         case GT_ASSET_FOREX:  return "FOREX";
         case GT_ASSET_GOLD:   return "METAL (XAU)";
         case GT_ASSET_SILVER: return "METAL (XAG)";
         case GT_ASSET_INDEX:  return "INDEX";
         case GT_ASSET_CRYPTO: return "CRYPTO";
         case GT_ASSET_CFD:    return "CFD";
         case GT_ASSET_CUSTOM: return "CUSTOM";
         default:              return "AUTO";
      }
   }

   double PipsToPrice(const double pips) const { return pips * m_pipSize; }

   double PriceToPips(const double priceDiff) const
   {
      if(m_pipSize <= 0.0) return 0.0;
      return priceDiff / m_pipSize;
   }

   double PipsToPoints(const double pips) const { return pips * m_pointsPerPip; }

   double PointsToPips(const double points) const
   {
      if(m_pointsPerPip <= 0.0) return 0.0;
      return points / m_pointsPerPip;
   }

   double GetPipValuePerLot() const
   {
      double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize > 0.0 && tickVal > 0.0)
         return (m_pipSize / tickSize) * tickVal;

      double contract = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contract > 0.0)
         return contract * m_pipSize;

      return 10.0;
   }

   double CalcMoneyForPips(const double lots, const double pips) const
   {
      return lots * pips * GetPipValuePerLot();
   }

   double NormalizePrice(const double price) const
   {
      double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize > 0.0)
         return NormalizeDouble(MathRound(price / tickSize) * tickSize, m_digits);
      return NormalizeDouble(price, m_digits);
   }

   double NormalizeLot(const double rawLot) const
   {
      double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      if(minLot <= 0.0)  minLot  = 0.01;
      if(maxLot <= 0.0)  maxLot  = 100.0;
      if(lotStep <= 0.0) lotStep = 0.01;

      double clamped = MathMax(minLot, MathMin(maxLot, rawLot));
      double steps   = MathFloor((clamped + 1e-10) / lotStep);
      double norm    = steps * lotStep;
      if(norm < minLot) norm = minLot;
      if(norm > maxLot) norm = maxLot;

      int lotDigits = 2;
      if(lotStep >= 1.0)       lotDigits = 0;
      else if(lotStep >= 0.1)  lotDigits = 1;
      else if(lotStep >= 0.01) lotDigits = 2;
      else                     lotDigits = 3;

      return NormalizeDouble(norm, lotDigits);
   }

   double CalcNextRecoveryLot(const double prevLot, const double multiplier) const
   {
      double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      if(minLot <= 0.0)  minLot  = 0.01;
      if(maxLot <= 0.0)  maxLot  = 100.0;
      if(lotStep <= 0.0) lotStep = 0.01;

      double base = (prevLot > 0.0) ? prevLot : minLot;
      double raw  = base * multiplier;
      double next = MathRound(raw / lotStep) * lotStep;

      if(multiplier > 1.0 && next <= base + 1e-10)
         next = base + lotStep;

      return NormalizeLot(MathMin(maxLot, MathMax(minLot, next)));
   }

   double GetSpreadPips() const
   {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(ask <= 0.0 || bid <= 0.0) return 0.0;
      return PriceToPips(ask - bid);
   }

   double GetMinStopPips() const
   {
      long stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      return PointsToPips((double)stopsLevel);
   }
};

//+------------------------------------------------------------------+
//| CConfigValidator                                                 |
//+------------------------------------------------------------------+
class CConfigValidator
{
public:
   static SValidationResult ValidateInit(const CPipConverter &pipConv,
                                         const ENUM_GT_SLTP_MODE sltpMode,
                                         const ENUM_GT_RR_MODE rrMode,
                                         const double customRR,
                                         const double fixedSLPips,
                                         const double fixedTPPips,
                                         const double gridStepPips,
                                         const double initialLot,
                                         const double multiplier,
                                         const int    maxLevel,
                                         const int    maxOpenPositions,
                                         const bool   strictRRReject)
   {
      SValidationResult res;
      res.Reset();

      double targetRR = GT_ResolveRR(rrMode, customRR);

      if(gridStepPips <= 0.0)
      {
         res.isValid      = false;
         res.errorMessage = "Grid Step harus lebih besar dari 0 pip.";
         return res;
      }

      if(targetRR <= 0.0)
      {
         res.isValid      = false;
         res.errorMessage = "Risk Reward (RR) harus lebih besar dari 0.";
         return res;
      }

      double minLot = SymbolInfoDouble(pipConv.SymbolName(), SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(pipConv.SymbolName(), SYMBOL_VOLUME_MAX);
      if(minLot > 0.0 && initialLot < minLot)
      {
         res.isValid      = false;
         res.errorMessage = StringFormat("Lot Awal (%.2f) lebih kecil dari minimum broker (%.2f).", initialLot, minLot);
         return res;
      }
      if(maxLot > 0.0 && initialLot > maxLot)
      {
         res.isValid      = false;
         res.errorMessage = StringFormat("Lot Awal (%.2f) melebihi maksimum broker (%.2f).", initialLot, maxLot);
         return res;
      }

      if(multiplier < 1.0)
      {
         res.isValid      = false;
         res.errorMessage = StringFormat("Multiplier Lot (%.2f) tidak boleh kurang dari 1.0.", multiplier);
         return res;
      }

      if(maxLevel < 0)
      {
         res.isValid      = false;
         res.errorMessage = "Max Martingale Level tidak boleh negatif.";
         return res;
      }

      if(maxOpenPositions < 1)
      {
         res.isValid      = false;
         res.errorMessage = "Max Open Positions minimal harus 1.";
         return res;
      }

      double effSLPips = fixedSLPips;
      double effTPPips = fixedTPPips;

      if(sltpMode == GT_SLTP_RISK_REWARD)
      {
         if(effSLPips <= 0.0)
         {
            res.isValid      = false;
            res.errorMessage = "Mode Risk Reward memerlukan Fixed SL > 0 pip.";
            return res;
         }
         effTPPips = effSLPips * targetRR;
      }
      else if(sltpMode == GT_SLTP_FIXED_PIP)
      {
         if(effSLPips <= 0.0 || effTPPips <= 0.0)
         {
            res.isValid      = false;
            res.errorMessage = "Mode Fixed Pip memerlukan SL > 0 pip dan TP > 0 pip.";
            return res;
         }
      }
      else
      {
         if(effSLPips > 0.0 && effTPPips <= 0.0)
            effTPPips = effSLPips * targetRR;
      }

      if(effTPPips > 0.0 && effTPPips + 1e-6 < gridStepPips)
      {
         res.isValid      = false;
         res.errorMessage = StringFormat("TP tidak boleh lebih kecil dari Grid Step (TP=%.1f pip < Grid Step=%.1f pip)",
                                         effTPPips, gridStepPips);
         return res;
      }

      if(effSLPips > 0.0 && effTPPips > 0.0)
      {
         double actualRR   = effTPPips / effSLPips;
         double expectedTP = effSLPips * targetRR;

         if(MathAbs(actualRR - targetRR) > 0.05)
         {
            res.hasWarning     = true;
            res.warningMessage = StringFormat("WARNING: RR tidak sesuai dengan SL dan TP! (SL=%.1f, TP=%.1f -> Aktual 1:%.2f, Target RR 1:%.2f -> TP seharusnya %.1f pip)",
                                              effSLPips, effTPPips, actualRR, targetRR, expectedTP);
            if(strictRRReject)
            {
               res.isValid      = false;
               res.errorMessage = res.warningMessage;
               return res;
            }
         }
      }

      double minStopPips = pipConv.GetMinStopPips();
      if(minStopPips > 0.0 && effSLPips > 0.0 && effSLPips < minStopPips)
      {
         res.hasWarning = true;
         string stopWarn = StringFormat("WARNING: SL (%.1f pip) lebih kecil dari StopsLevel broker (%.1f pip).",
                                        effSLPips, minStopPips);
         res.warningMessage = (res.warningMessage == "") ? stopWarn : (res.warningMessage + " | " + stopWarn);
      }

      return res;
   }

   static SValidationResult ValidateRuntimeSLTP(const double slPips,
                                                const double tpPips,
                                                const double gridStepPips,
                                                const double targetRR,
                                                const bool   strictRRReject)
   {
      SValidationResult res;
      res.Reset();

      if(tpPips > 0.0 && tpPips + 1e-6 < gridStepPips)
      {
         res.isValid      = false;
         res.errorMessage = StringFormat("TP tidak boleh lebih kecil dari Grid Step (Runtime TP=%.1f pip < Grid Step=%.1f pip)",
                                         tpPips, gridStepPips);
         return res;
      }

      if(slPips > 0.0 && tpPips > 0.0 && targetRR > 0.0)
      {
         double actualRR = tpPips / slPips;
         if(MathAbs(actualRR - targetRR) > 0.10)
         {
            res.hasWarning     = true;
            res.warningMessage = StringFormat("WARNING: RR tidak sesuai dengan SL dan TP! (SL=%.1f, TP=%.1f -> Aktual 1:%.2f vs Target 1:%.2f)",
                                              slPips, tpPips, actualRR, targetRR);
            if(strictRRReject)
            {
               res.isValid      = false;
               res.errorMessage = res.warningMessage;
            }
         }
      }

      return res;
   }
};

//+------------------------------------------------------------------+
//| Market Structure helper structs                                  |
//+------------------------------------------------------------------+
struct SSwingPoint
{
   int      barIndex;
   datetime time;
   double   price;
   bool     isHigh;
};

struct SZoneBox
{
   bool     active;
   bool     isBull;
   bool     inverted;
   int      formedIdx;
   int      eventIdx;
   double   high;
   double   low;
};

//+------------------------------------------------------------------+
//| CMarketStructure                                                 |
//+------------------------------------------------------------------+
class CMarketStructure
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   ENUM_TIMEFRAMES m_crtTF;
   int             m_extStrength;
   int             m_intStrength;
   int             m_lookbackBars;
   int             m_signalWindowBars;
   double          m_eqTolerancePips;
   double          m_minFVGPips;

   bool            m_useAsiaKZ;
   string          m_asiaWindow;
   bool            m_useLondonKZ;
   string          m_londonWindow;
   bool            m_useNYAMKZ;
   string          m_nyamWindow;
   bool            m_useNYPMKZ;
   string          m_nypmWindow;

   SMarketContext  m_ctx;

   bool ParseWindow(const string spec, int &startMin, int &endMin) const
   {
      string parts[];
      if(StringSplit(spec, '-', parts) != 2)
         return false;

      string sParts[], eParts[];
      if(StringSplit(parts[0], ':', sParts) != 2) return false;
      if(StringSplit(parts[1], ':', eParts) != 2) return false;

      int sh = (int)StringToInteger(sParts[0]);
      int sm = (int)StringToInteger(sParts[1]);
      int eh = (int)StringToInteger(eParts[0]);
      int em = (int)StringToInteger(eParts[1]);

      if(sh < 0 || sh > 23 || sm < 0 || sm > 59 || eh < 0 || eh > 24 || em < 0 || em > 59)
         return false;

      startMin = sh * 60 + sm;
      endMin   = eh * 60 + em;
      return true;
   }

   bool IsMinuteInWindow(const int nowMin, const string spec) const
   {
      int sMin = 0, eMin = 0;
      if(!ParseWindow(spec, sMin, eMin))
         return false;

      if(sMin <= eMin)
         return (nowMin >= sMin && nowMin < eMin);
      return (nowMin >= sMin || nowMin < eMin);
   }

   void EvaluateKillZone(const datetime serverTime, SMarketContext &ctx) const
   {
      MqlDateTime dt;
      TimeToStruct(serverTime, dt);
      int nowMin = dt.hour * 60 + dt.min;

      ctx.inKillZone   = false;
      ctx.killZoneName = "OFF";

      if(m_useLondonKZ && IsMinuteInWindow(nowMin, m_londonWindow))
      {
         ctx.inKillZone   = true;
         ctx.killZoneName = "LONDON KZ";
         return;
      }
      if(m_useNYAMKZ && IsMinuteInWindow(nowMin, m_nyamWindow))
      {
         ctx.inKillZone   = true;
         ctx.killZoneName = "NY AM KZ";
         return;
      }
      if(m_useNYPMKZ && IsMinuteInWindow(nowMin, m_nypmWindow))
      {
         ctx.inKillZone   = true;
         ctx.killZoneName = "NY PM KZ";
         return;
      }
      if(m_useAsiaKZ && IsMinuteInWindow(nowMin, m_asiaWindow))
      {
         ctx.inKillZone   = true;
         ctx.killZoneName = "ASIA KZ";
         return;
      }
   }

   void CollectSwings(const MqlRates &rates[],
                      const int count,
                      const int strength,
                      SSwingPoint &swings[]) const
   {
      ArrayResize(swings, 0);
      if(count < strength * 2 + 1)
         return;

      for(int i = strength; i < count - strength; i++)
      {
         bool isSwingHigh = true;
         bool isSwingLow  = true;

         for(int k = 1; k <= strength; k++)
         {
            if(rates[i].high <= rates[i - k].high || rates[i].high < rates[i + k].high)
               isSwingHigh = false;
            if(rates[i].low >= rates[i - k].low || rates[i].low > rates[i + k].low)
               isSwingLow = false;
            if(!isSwingHigh && !isSwingLow)
               break;
         }

         if(isSwingHigh)
         {
            int sz = ArraySize(swings);
            ArrayResize(swings, sz + 1);
            swings[sz].barIndex = i;
            swings[sz].time     = rates[i].time;
            swings[sz].price    = rates[i].high;
            swings[sz].isHigh   = true;
         }
         if(isSwingLow)
         {
            int sz = ArraySize(swings);
            ArrayResize(swings, sz + 1);
            swings[sz].barIndex = i;
            swings[sz].time     = rates[i].time;
            swings[sz].price    = rates[i].low;
            swings[sz].isHigh   = false;
         }
      }
   }

public:
   CMarketStructure()
   {
      m_symbol           = _Symbol;
      m_tf               = PERIOD_CURRENT;
      m_crtTF            = PERIOD_H1;
      m_extStrength      = 5;
      m_intStrength      = 2;
      m_lookbackBars     = 140;
      m_signalWindowBars = 8;
      m_eqTolerancePips  = 3.0;
      m_minFVGPips       = 1.0;
      m_useAsiaKZ        = false;
      m_asiaWindow       = "01:00-08:00";
      m_useLondonKZ      = true;
      m_londonWindow     = "09:00-12:00";
      m_useNYAMKZ        = true;
      m_nyamWindow       = "15:00-18:00";
      m_useNYPMKZ        = true;
      m_nypmWindow       = "21:00-22:00";
      m_ctx.Reset();
   }

   void Init(const string symbol,
             const ENUM_TIMEFRAMES tf,
             const ENUM_TIMEFRAMES crtTF,
             const int extStrength,
             const int intStrength,
             const int lookbackBars,
             const int signalWindowBars,
             const double eqTolerancePips,
             const double minFVGPips,
             const bool useAsiaKZ,   const string asiaWindow,
             const bool useLondonKZ, const string londonWindow,
             const bool useNYAMKZ,   const string nyamWindow,
             const bool useNYPMKZ,   const string nypmWindow)
   {
      m_symbol           = symbol;
      m_tf               = tf;
      m_crtTF            = crtTF;
      m_extStrength      = MathMax(2, extStrength);
      m_intStrength      = MathMax(1, intStrength);
      m_lookbackBars     = MathMax(60, lookbackBars);
      m_signalWindowBars = MathMax(2, signalWindowBars);
      m_eqTolerancePips  = MathMax(0.5, eqTolerancePips);
      m_minFVGPips       = MathMax(0.2, minFVGPips);
      m_useAsiaKZ        = useAsiaKZ;
      m_asiaWindow       = asiaWindow;
      m_useLondonKZ      = useLondonKZ;
      m_londonWindow     = londonWindow;
      m_useNYAMKZ        = useNYAMKZ;
      m_nyamWindow       = nyamWindow;
      m_useNYPMKZ        = useNYPMKZ;
      m_nypmWindow       = nypmWindow;
      m_ctx.Reset();
   }

   SMarketContext GetContext() const
   {
      return m_ctx;
   }

   bool Update(const CPipConverter &pipConv)
   {
      SMarketContext ctx;
      ctx.Reset();

      MqlRates rates[];
      ArraySetAsSeries(rates, false);
      int copied = CopyRates(m_symbol, m_tf, 1, m_lookbackBars, rates);
      if(copied < MathMax(30, m_extStrength * 3))
         return false;

      int lastIdx      = copied - 1;
      int recentCutoff = MathMax(0, lastIdx - m_signalWindowBars + 1);
      double eqTolPx   = pipConv.PipsToPrice(m_eqTolerancePips);
      double minFVGPx  = pipConv.PipsToPrice(m_minFVGPips);

      double liveBid   = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double refPrice  = (liveBid > 0.0) ? liveBid : rates[lastIdx].close;

      ctx.barTime    = rates[lastIdx].time;
      ctx.closePrice = rates[lastIdx].close;
      ctx.highPrice  = rates[lastIdx].high;
      ctx.lowPrice   = rates[lastIdx].low;

      double sumBody = 0.0;
      int bodyStart  = MathMax(0, copied - 40);
      for(int i = bodyStart; i < copied; i++)
         sumBody += MathAbs(rates[i].close - rates[i].open);
      double avgBody = (copied - bodyStart > 0) ? (sumBody / (copied - bodyStart)) : pipConv.PipsToPrice(5.0);
      if(avgBody <= 0.0) avgBody = pipConv.PipsToPrice(2.0);

      //================================================================
      // 1. EXTERNAL STRUCTURE: BOS, CHoCH, xBSL, xSSL, EQH, EQL, MB
      //================================================================
      SSwingPoint extSwings[];
      CollectSwings(rates, copied, m_extStrength, extSwings);

      double activeExtHigh = 0.0, prevExtHigh = 0.0;
      double activeExtLow  = 0.0, prevExtLow  = 0.0;
      int    activeExtHighIdx = -1, activeExtLowIdx = -1;
      bool   extHighBroken = false, extLowBroken = false;
      int    extTrend = 0;

      double eqhPrice = 0.0; int eqhIdx = -1;
      double eqlPrice = 0.0; int eqlIdx = -1;

      double bullMBHigh = 0.0, bullMBLow = 0.0; bool bullMBValid = false;
      double bearMBHigh = 0.0, bearMBLow = 0.0; bool bearMBValid = false;

      SZoneBox bullOB; ZeroMemory(bullOB);
      SZoneBox bearOB; ZeroMemory(bearOB);

      int swingCursor = 0;
      int nExtSwings  = ArraySize(extSwings);

      for(int i = 0; i < copied; i++)
      {
         while(swingCursor < nExtSwings && extSwings[swingCursor].barIndex + m_extStrength <= i)
         {
            SSwingPoint sp = extSwings[swingCursor];
            if(sp.isHigh)
            {
               if(activeExtHigh > 0.0 && MathAbs(sp.price - activeExtHigh) <= eqTolPx)
               {
                  ctx.eqhDetected = true;
                  eqhPrice = MathMax(sp.price, activeExtHigh);
                  eqhIdx   = sp.barIndex;
               }
               if(extTrend == 1 && activeExtHigh > 0.0 && sp.price < activeExtHigh)
               {
                  bearMBHigh  = rates[sp.barIndex].high;
                  bearMBLow   = rates[sp.barIndex].low;
                  bearMBValid = true;
               }
               prevExtHigh      = activeExtHigh;
               activeExtHigh    = sp.price;
               activeExtHighIdx = sp.barIndex;
               extHighBroken    = false;
            }
            else
            {
               if(activeExtLow > 0.0 && MathAbs(sp.price - activeExtLow) <= eqTolPx)
               {
                  ctx.eqlDetected = true;
                  eqlPrice = MathMin(sp.price, activeExtLow);
                  eqlIdx   = sp.barIndex;
               }
               if(extTrend == -1 && activeExtLow > 0.0 && sp.price > activeExtLow)
               {
                  bullMBHigh  = rates[sp.barIndex].high;
                  bullMBLow   = rates[sp.barIndex].low;
                  bullMBValid = true;
               }
               prevExtLow      = activeExtLow;
               activeExtLow    = sp.price;
               activeExtLowIdx = sp.barIndex;
               extLowBroken    = false;
            }
            swingCursor++;
         }

         if(activeExtHigh > 0.0 && rates[i].high > activeExtHigh && rates[i].close < activeExtHigh)
         {
            if(i >= recentCutoff)
            {
               ctx.xBSL      = true;
               ctx.sweepBear = true;
            }
         }
         if(activeExtLow > 0.0 && rates[i].low < activeExtLow && rates[i].close > activeExtLow)
         {
            if(i >= recentCutoff)
            {
               ctx.xSSL      = true;
               ctx.sweepBull = true;
            }
         }

         if(eqhPrice > 0.0 && i > eqhIdx && rates[i].high > eqhPrice && rates[i].close < eqhPrice)
         {
            if(i >= recentCutoff)
            {
               ctx.eqhSweptBear = true;
               ctx.xBSL         = true;
               ctx.sweepBear    = true;
            }
         }
         if(eqlPrice > 0.0 && i > eqlIdx && rates[i].low < eqlPrice && rates[i].close > eqlPrice)
         {
            if(i >= recentCutoff)
            {
               ctx.eqlSweptBull = true;
               ctx.xSSL         = true;
               ctx.sweepBull    = true;
            }
         }

         if(activeExtHigh > 0.0 && !extHighBroken && rates[i].close > activeExtHigh)
         {
            extHighBroken = true;
            bool wasBear  = (extTrend == -1);
            extTrend      = 1;

            if(i >= recentCutoff)
            {
               if(wasBear) ctx.chochBull = true;
               else        ctx.bosBull   = true;
            }

            for(int k = i - 1; k >= MathMax(0, i - 15); k--)
            {
               if(rates[k].close < rates[k].open)
               {
                  bullOB.active    = true;
                  bullOB.isBull    = true;
                  bullOB.inverted  = false;
                  bullOB.formedIdx = k;
                  bullOB.high      = rates[k].high;
                  bullOB.low       = rates[k].low;
                  break;
               }
            }
         }

         if(activeExtLow > 0.0 && !extLowBroken && rates[i].close < activeExtLow)
         {
            extLowBroken = true;
            bool wasBull = (extTrend == 1);
            extTrend     = -1;

            if(i >= recentCutoff)
            {
               if(wasBull) ctx.chochBear = true;
               else        ctx.bosBear   = true;
            }

            for(int k = i - 1; k >= MathMax(0, i - 15); k--)
            {
               if(rates[k].close > rates[k].open)
               {
                  bearOB.active    = true;
                  bearOB.isBull    = false;
                  bearOB.inverted  = false;
                  bearOB.formedIdx = k;
                  bearOB.high      = rates[k].high;
                  bearOB.low       = rates[k].low;
                  break;
               }
            }
         }

         if(bullOB.active && i > bullOB.formedIdx && rates[i].close < bullOB.low)
         {
            bullOB.active   = false;
            bullOB.inverted = true;
            bullOB.eventIdx = i;
            if(i >= recentCutoff)
               ctx.bearBreakerActive = true;
         }
         if(bearOB.active && i > bearOB.formedIdx && rates[i].close > bearOB.high)
         {
            bearOB.active   = false;
            bearOB.inverted = true;
            bearOB.eventIdx = i;
            if(i >= recentCutoff)
               ctx.bullBreakerActive = true;
         }
      }

      ctx.extTrend    = extTrend;
      ctx.lastExtHigh = activeExtHigh;
      ctx.lastExtLow  = activeExtLow;

      if(bullOB.active)
      {
         ctx.bullOBValid = true;
         ctx.bullOBHigh  = bullOB.high;
         ctx.bullOBLow   = bullOB.low;
         if(refPrice <= bullOB.high && refPrice >= bullOB.low)
            ctx.atBullOB = true;
      }
      if(bearOB.active)
      {
         ctx.bearOBValid = true;
         ctx.bearOBHigh  = bearOB.high;
         ctx.bearOBLow   = bearOB.low;
         if(refPrice <= bearOB.high && refPrice >= bearOB.low)
            ctx.atBearOB = true;
      }

      if(bullOB.inverted && (lastIdx - bullOB.eventIdx <= m_signalWindowBars * 2))
         ctx.bearBreakerActive = true;
      if(bearOB.inverted && (lastIdx - bearOB.eventIdx <= m_signalWindowBars * 2))
         ctx.bullBreakerActive = true;

      if(bullMBValid && (ctx.chochBull || ctx.bosBull) && rates[lastIdx].low <= bullMBHigh && rates[lastIdx].close >= bullMBLow)
         ctx.bullMB = true;
      if(bearMBValid && (ctx.chochBear || ctx.bosBear) && rates[lastIdx].high >= bearMBLow && rates[lastIdx].close <= bearMBHigh)
         ctx.bearMB = true;

      //================================================================
      // 2. INTERNAL STRUCTURE (iBOS / iCHoCH) & IDM (INDUCEMENT SWEEP)
      //================================================================
      SSwingPoint intSwings[];
      CollectSwings(rates, copied, m_intStrength, intSwings);

      double activeIntHigh = 0.0, activeIntLow = 0.0;
      bool   intHighBroken = false, intLowBroken = false;
      int    intTrend = 0;
      int    intCursor = 0;
      int    nIntSwings = ArraySize(intSwings);

      for(int i = 0; i < copied; i++)
      {
         while(intCursor < nIntSwings && intSwings[intCursor].barIndex + m_intStrength <= i)
         {
            if(intSwings[intCursor].isHigh)
            {
               activeIntHigh = intSwings[intCursor].price;
               intHighBroken = false;
            }
            else
            {
               activeIntLow = intSwings[intCursor].price;
               intLowBroken = false;
            }
            intCursor++;
         }

         if(activeIntHigh > 0.0 && rates[i].high > activeIntHigh && rates[i].close < activeIntHigh)
         {
            if(i >= recentCutoff)
            {
               ctx.idmSweptBear = true;
               ctx.sweepBear    = true;
            }
         }
         if(activeIntLow > 0.0 && rates[i].low < activeIntLow && rates[i].close > activeIntLow)
         {
            if(i >= recentCutoff)
            {
               ctx.idmSweptBull = true;
               ctx.sweepBull    = true;
            }
         }

         if(activeIntHigh > 0.0 && !intHighBroken && rates[i].close > activeIntHigh)
         {
            intHighBroken = true;
            bool wasBear  = (intTrend == -1);
            intTrend      = 1;
            if(i >= recentCutoff)
            {
               if(wasBear) ctx.ichochBull = true;
               else        ctx.ibosBull   = true;
            }
         }
         if(activeIntLow > 0.0 && !intLowBroken && rates[i].close < activeIntLow)
         {
            intLowBroken = true;
            bool wasBull = (intTrend == 1);
            intTrend     = -1;
            if(i >= recentCutoff)
            {
               if(wasBull) ctx.ichochBear = true;
               else        ctx.ibosBear   = true;
            }
         }
      }

      if(extTrend == 1 && activeIntLow > 0.0 && (ctx.xBSL || ctx.chochBear || ctx.ichochBear))
      {
         for(int i = recentCutoff; i <= lastIdx; i++)
         {
            if(rates[i].low < activeIntLow)
            {
               ctx.idmSweptBear = true;
               break;
            }
         }
      }
      if(extTrend == -1 && activeIntHigh > 0.0 && (ctx.xSSL || ctx.chochBull || ctx.ichochBull))
      {
         for(int i = recentCutoff; i <= lastIdx; i++)
         {
            if(rates[i].high > activeIntHigh)
            {
               ctx.idmSweptBull = true;
               break;
            }
         }
      }

      ctx.intTrend     = intTrend;
      ctx.lastIntHigh  = activeIntHigh;
      ctx.lastIntLow   = activeIntLow;
      ctx.idmHighLevel = activeIntHigh;
      ctx.idmLowLevel  = activeIntLow;

      //================================================================
      // 3. FVG (BISI/SIBI) & IFVG (INVERSION FVG)
      //================================================================
      SZoneBox fvgs[];
      ArrayResize(fvgs, 0);

      for(int i = 2; i < copied; i++)
      {
         if(rates[i].low - rates[i - 2].high >= minFVGPx)
         {
            int sz = ArraySize(fvgs);
            ArrayResize(fvgs, sz + 1);
            fvgs[sz].active    = true;
            fvgs[sz].isBull    = true;
            fvgs[sz].inverted  = false;
            fvgs[sz].formedIdx = i;
            fvgs[sz].eventIdx  = -1;
            fvgs[sz].high      = rates[i].low;
            fvgs[sz].low       = rates[i - 2].high;
         }
         else if(rates[i - 2].low - rates[i].high >= minFVGPx)
         {
            int sz = ArraySize(fvgs);
            ArrayResize(fvgs, sz + 1);
            fvgs[sz].active    = true;
            fvgs[sz].isBull    = false;
            fvgs[sz].inverted  = false;
            fvgs[sz].formedIdx = i;
            fvgs[sz].eventIdx  = -1;
            fvgs[sz].high      = rates[i - 2].low;
            fvgs[sz].low       = rates[i].high;
         }

         int nF = ArraySize(fvgs);
         for(int f = 0; f < nF; f++)
         {
            if(!fvgs[f].active || i <= fvgs[f].formedIdx)
               continue;

            if(fvgs[f].isBull && rates[i].close < fvgs[f].low)
            {
               fvgs[f].active   = false;
               fvgs[f].inverted = true;
               fvgs[f].eventIdx = i;
               if(i >= recentCutoff)
                  ctx.bearIFVG = true;
            }
            else if(!fvgs[f].isBull && rates[i].close > fvgs[f].high)
            {
               fvgs[f].active   = false;
               fvgs[f].inverted = true;
               fvgs[f].eventIdx = i;
               if(i >= recentCutoff)
                  ctx.bullIFVG = true;
            }
         }
      }

      for(int f = ArraySize(fvgs) - 1; f >= 0; f--)
      {
         if(fvgs[f].active && fvgs[f].isBull && !ctx.bullFVGValid)
         {
            ctx.bullFVGValid = true;
            ctx.bullFVGHigh  = fvgs[f].high;
            ctx.bullFVGLow   = fvgs[f].low;
         }
         if(fvgs[f].active && !fvgs[f].isBull && !ctx.bearFVGValid)
         {
            ctx.bearFVGValid = true;
            ctx.bearFVGHigh  = fvgs[f].high;
            ctx.bearFVGLow   = fvgs[f].low;
         }
         if(ctx.bullFVGValid && ctx.bearFVGValid)
            break;
      }

      //================================================================
      // 4. VOLUME IMBALANCE (VI) & LIQUIDITY VOID
      //================================================================
      double viMinGap = pipConv.PointSize() * 2.0;
      for(int i = MathMax(1, recentCutoff); i <= lastIdx; i++)
      {
         double prevBodyTop = MathMax(rates[i - 1].open, rates[i - 1].close);
         double prevBodyBot = MathMin(rates[i - 1].open, rates[i - 1].close);
         double curBodyTop  = MathMax(rates[i].open, rates[i].close);
         double curBodyBot  = MathMin(rates[i].open, rates[i].close);

         if(curBodyBot - prevBodyTop >= viMinGap && rates[i].close > rates[i].open)
            ctx.bullVI = true;
         if(prevBodyBot - curBodyTop >= viMinGap && rates[i].close < rates[i].open)
            ctx.bearVI = true;

         double bCur  = MathAbs(rates[i].close - rates[i].open);
         double bPrev = MathAbs(rates[i - 1].close - rates[i - 1].open);
         if(bCur >= avgBody * 1.5 && bPrev >= avgBody * 1.5)
         {
            if(rates[i].close > rates[i].open && rates[i - 1].close > rates[i - 1].open)
               ctx.bullVoid = true;
            if(rates[i].close < rates[i].open && rates[i - 1].close < rates[i - 1].open)
               ctx.bearVoid = true;
         }
      }

      //================================================================
      // 5. DEALING RANGE: PREMIUM, DISCOUNT, EQ50, OTE
      //================================================================
      double rHigh = activeExtHigh;
      double rLow  = activeExtLow;
      if(rHigh <= rLow || rHigh <= 0.0 || rLow <= 0.0)
      {
         rHigh = rates[lastIdx].high;
         rLow  = rates[lastIdx].low;
         for(int i = MathMax(0, copied - 50); i < copied; i++)
         {
            if(rates[i].high > rHigh) rHigh = rates[i].high;
            if(rates[i].low  < rLow)  rLow  = rates[i].low;
         }
      }

      if(rHigh > rLow)
      {
         double span    = rHigh - rLow;
         ctx.rangeHigh  = rHigh;
         ctx.rangeLow   = rLow;
         ctx.eq50       = rLow + span * 0.50;
         ctx.inPremium  = (refPrice > ctx.eq50);
         ctx.inDiscount = (refPrice <= ctx.eq50);

         double bullOTETop = rHigh - span * 0.618;
         double bullOTEBot = rHigh - span * 0.786;
         ctx.inBullOTE     = (refPrice >= bullOTEBot && refPrice <= bullOTETop);

         double bearOTEBot = rLow + span * 0.618;
         double bearOTETop = rLow + span * 0.786;
         ctx.inBearOTE     = (refPrice >= bearOTEBot && refPrice <= bearOTETop);
      }

      //================================================================
      // 6. HTF LIQUIDITY LEVELS: PDH, PDL, PWH, PWL + SWEEP CHECKS
      //================================================================
      MqlRates d1Rates[], w1Rates[];
      ArraySetAsSeries(d1Rates, true);
      ArraySetAsSeries(w1Rates, true);

      if(CopyRates(m_symbol, PERIOD_D1, 1, 1, d1Rates) == 1)
      {
         ctx.pdh = d1Rates[0].high;
         ctx.pdl = d1Rates[0].low;
         for(int i = recentCutoff; i <= lastIdx; i++)
         {
            if(rates[i].high > ctx.pdh && rates[i].close < ctx.pdh)
            {
               ctx.pdhSweptBear = true;
               ctx.xBSL         = true;
               ctx.sweepBear    = true;
            }
            if(rates[i].low < ctx.pdl && rates[i].close > ctx.pdl)
            {
               ctx.pdlSweptBull = true;
               ctx.xSSL         = true;
               ctx.sweepBull    = true;
            }
         }
      }

      if(CopyRates(m_symbol, PERIOD_W1, 1, 1, w1Rates) == 1)
      {
         ctx.pwh = w1Rates[0].high;
         ctx.pwl = w1Rates[0].low;
         for(int i = recentCutoff; i <= lastIdx; i++)
         {
            if(rates[i].high > ctx.pwh && rates[i].close < ctx.pwh)
            {
               ctx.pwhSweptBear = true;
               ctx.xBSL         = true;
               ctx.sweepBear    = true;
            }
            if(rates[i].low < ctx.pwl && rates[i].close > ctx.pwl)
            {
               ctx.pwlSweptBull = true;
               ctx.xSSL         = true;
               ctx.sweepBull    = true;
            }
         }
      }

      //================================================================
      // 7. CRT (CANDLE RANGE THEORY)
      //================================================================
      MqlRates crtRates[];
      ArraySetAsSeries(crtRates, true);
      if(CopyRates(m_symbol, m_crtTF, 1, 1, crtRates) == 1)
      {
         ctx.crtRefHigh = crtRates[0].high;
         ctx.crtRefLow  = crtRates[0].low;

         for(int i = recentCutoff; i <= lastIdx; i++)
         {
            if(rates[i].low < ctx.crtRefLow && rates[i].close > ctx.crtRefLow && rates[i].close < ctx.crtRefHigh)
               ctx.crtBull = true;

            if(rates[i].high > ctx.crtRefHigh && rates[i].close < ctx.crtRefHigh && rates[i].close > ctx.crtRefLow)
               ctx.crtBear = true;
         }
      }

      //================================================================
      // 8. KILLZONE EVALUATION (Server/Tester Time)
      //================================================================
      EvaluateKillZone(TimeCurrent(), ctx);

      m_ctx = ctx;
      return true;
   }

   void UpdateLiveState(const CPipConverter &pipConv)
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(bid > 0.0)
      {
         if(m_ctx.rangeHigh > m_ctx.rangeLow)
         {
            double span      = m_ctx.rangeHigh - m_ctx.rangeLow;
            m_ctx.eq50       = m_ctx.rangeLow + span * 0.50;
            m_ctx.inPremium  = (bid > m_ctx.eq50);
            m_ctx.inDiscount = (bid <= m_ctx.eq50);

            double bullOTETop = m_ctx.rangeHigh - span * 0.618;
            double bullOTEBot = m_ctx.rangeHigh - span * 0.786;
            m_ctx.inBullOTE   = (bid >= bullOTEBot && bid <= bullOTETop);

            double bearOTEBot = m_ctx.rangeLow + span * 0.618;
            double bearOTETop = m_ctx.rangeLow + span * 0.786;
            m_ctx.inBearOTE   = (bid >= bearOTEBot && bid <= bearOTETop);
         }

         m_ctx.atBullOB = (m_ctx.bullOBValid && bid <= m_ctx.bullOBHigh && bid >= m_ctx.bullOBLow);
         m_ctx.atBearOB = (m_ctx.bearOBValid && bid <= m_ctx.bearOBHigh && bid >= m_ctx.bearOBLow);
      }

      EvaluateKillZone(TimeCurrent(), m_ctx);
   }
};

#define GT_VIS_PREFIX "GTRE_VIS_"

//+------------------------------------------------------------------+
//| CInternalSignalEngine (All-in-One ICT+SMC+CRT)                   |
//+------------------------------------------------------------------+
class CInternalSignalEngine
{
private:
   string                    m_symbol;
   ENUM_TIMEFRAMES           m_tf;
   int                       m_signalShift;
   ENUM_GT_ENTRY_SENSITIVITY m_sensitivity;
   double                    m_slBufferPips;
   double                    m_defaultSLPips;
   double                    m_targetRR;
   double                    m_gridStepPips;
   bool                      m_drawVisuals;

   datetime                  m_lastEvaluatedBar;
   ENUM_GT_BIAS              m_prevBias;
   SIndicatorData            m_cachedData;
   datetime                  m_lastSignalArrowBar;

   void AppendToken(string &dst, const string token) const
   {
      if(token == "") return;
      if(dst == "" || dst == "-") dst = token;
      else dst += "+" + token;
   }

   void DrawHLine(const string name,
                  const double price,
                  const color clr,
                  const ENUM_LINE_STYLE style,
                  const string labelText) const
   {
      if(price <= 0.0)
      {
         ObjectDelete(0, name);
         return;
      }
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, labelText);
   }

   void DrawSignalArrow(const datetime barTime,
                        const double price,
                        const bool isBuy,
                        const string tooltip) const
   {
      string name = GT_VIS_PREFIX + (isBuy ? "BUY_" : "SELL_") + IntegerToString((long)barTime);
      if(ObjectFind(0, name) >= 0)
         return;

      ObjectCreate(0, name, isBuy ? OBJ_ARROW_UP : OBJ_ARROW_DOWN, 0, barTime, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? C'52,211,153' : C'248,113,113');
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
   }

   //--- ALASAN BIAS: sistem voting struktur. Bias hanya BULLISH/BEARISH jika selisih vote >= 2.
   //    Bias adalah GERBANG pertama: tanpa bias searah, sinyal BUY/SELL tidak pernah keluar.
   ENUM_GT_BIAS DetermineBias(const SMarketContext &ctx) const
   {
      int bullVotes = 0;
      int bearVotes = 0;

      // Tren struktur eksternal (swing besar): fondasi arah utama
      if(ctx.extTrend ==  1) bullVotes += 3;
      if(ctx.extTrend == -1) bearVotes += 3;

      // CHoCH = pembalikan struktur eksternal (bobot terbesar), BOS = kelanjutan tren
      if(ctx.chochBull) bullVotes += 4;
      if(ctx.chochBear) bearVotes += 4;
      if(ctx.bosBull)   bullVotes += 2;
      if(ctx.bosBear)   bearVotes += 2;

      // Struktur internal (swing kecil): konfirmasi lebih awal
      if(ctx.intTrend ==  1) bullVotes += 1;
      if(ctx.intTrend == -1) bearVotes += 1;
      if(ctx.ichochBull)     bullVotes += 2;
      if(ctx.ichochBear)     bearVotes += 2;

      // CRT valid hanya dihitung jika disertai sapuan likuiditas (manipulasi -> distribusi)
      if(ctx.crtBull && (ctx.xSSL || ctx.idmSweptBull)) bullVotes += 3;
      if(ctx.crtBear && (ctx.xBSL || ctx.idmSweptBear)) bearVotes += 3;
      // IFVG = FVG yang gagal bertahan lalu berbalik fungsi (support/resistance baru)
      if(ctx.bullIFVG) bullVotes += 1;
      if(ctx.bearIFVG) bearVotes += 1;

      if(bullVotes >= bearVotes + 2) return GT_BIAS_BULLISH;
      if(bearVotes >= bullVotes + 2) return GT_BIAS_BEARISH;
      return GT_BIAS_NEUTRAL;
   }

   //--- SL/TP struktural untuk ENTRY AWAL (L0): SL di balik OB / swing internal + buffer.
   //    Jarak SL ini disimpan di state siklus dan DIWARISI oleh semua Flip (v1.33).
   void ComputeStructuralSLTP(const bool isBuy,
                              const double refEntry,
                              const MqlRates &sigBar,
                              const SMarketContext &ctx,
                              const CPipConverter &pipConv,
                              double &outSL,
                              double &outTP) const
   {
      double bufPx   = pipConv.PipsToPrice(m_slBufferPips);
      double baseSL  = MathMax(5.0, m_defaultSLPips);
      double rr      = (m_targetRR > 0.0) ? m_targetRR : 2.0;
      double minSLForGrid = (rr > 0.0) ? (m_gridStepPips / rr) : m_gridStepPips;
      double minSLPx = pipConv.PipsToPrice(MathMax(MathMax(pipConv.GetMinStopPips() + 1.0, baseSL * 0.5), minSLForGrid));
      double maxSLPx = pipConv.PipsToPrice(MathMax(baseSL * 2.5, m_gridStepPips * 2.5));

      double slDistPx = pipConv.PipsToPrice(baseSL);

      if(isBuy)
      {
         double structLow = sigBar.low;
         if(ctx.bullOBValid && ctx.bullOBLow > 0.0 && ctx.bullOBLow < refEntry)
            structLow = MathMin(structLow, ctx.bullOBLow);
         else if(ctx.lastIntLow > 0.0 && ctx.lastIntLow < refEntry)
            structLow = MathMin(structLow, ctx.lastIntLow);

         double candSL = structLow - bufPx;
         double candDist = refEntry - candSL;
         if(candDist >= minSLPx && candDist <= maxSLPx)
            slDistPx = candDist;
         else if(candDist > maxSLPx)
            slDistPx = maxSLPx;
         else
            slDistPx = MathMax(minSLPx, pipConv.PipsToPrice(baseSL));

         slDistPx = pipConv.NormalizePrice(slDistPx);
         double tpDistPx = pipConv.NormalizePrice(slDistPx * rr);
         outSL = pipConv.NormalizePrice(refEntry - slDistPx);
         outTP = pipConv.NormalizePrice(refEntry + tpDistPx);
      }
      else
      {
         double structHigh = sigBar.high;
         if(ctx.bearOBValid && ctx.bearOBHigh > refEntry)
            structHigh = MathMax(structHigh, ctx.bearOBHigh);
         else if(ctx.lastIntHigh > refEntry)
            structHigh = MathMax(structHigh, ctx.lastIntHigh);

         double candSL = structHigh + bufPx;
         double candDist = candSL - refEntry;
         if(candDist >= minSLPx && candDist <= maxSLPx)
            slDistPx = candDist;
         else if(candDist > maxSLPx)
            slDistPx = maxSLPx;
         else
            slDistPx = MathMax(minSLPx, pipConv.PipsToPrice(baseSL));

         slDistPx = pipConv.NormalizePrice(slDistPx);
         double tpDistPx = pipConv.NormalizePrice(slDistPx * rr);
         outSL = pipConv.NormalizePrice(refEntry + slDistPx);
         outTP = pipConv.NormalizePrice(refEntry - tpDistPx);
      }
   }

public:
   CInternalSignalEngine()
   {
      m_symbol             = _Symbol;
      m_tf                 = PERIOD_CURRENT;
      m_signalShift        = 1;
      m_sensitivity        = GT_SENS_BALANCED;
      m_slBufferPips       = 3.0;
      m_defaultSLPips      = 20.0;
      m_targetRR           = 2.0;
      m_gridStepPips       = 20.0;
      m_drawVisuals        = true;
      m_lastEvaluatedBar   = 0;
      m_prevBias           = GT_BIAS_NEUTRAL;
      m_lastSignalArrowBar = 0;
      m_cachedData.Reset();
   }

   void Init(const string symbol,
             const ENUM_TIMEFRAMES tf,
             const int signalShift,
             const ENUM_GT_ENTRY_SENSITIVITY sensitivity,
             const double slBufferPips,
             const double defaultSLPips,
             const double targetRR,
             const double gridStepPips,
             const bool drawVisuals)
   {
      m_symbol             = symbol;
      m_tf                 = tf;
      m_signalShift        = MathMax(0, signalShift);
      m_sensitivity        = sensitivity;
      m_slBufferPips       = MathMax(0.5, slBufferPips);
      m_defaultSLPips      = MathMax(1.0, defaultSLPips);
      m_targetRR           = MathMax(0.5, targetRR);
      m_gridStepPips       = MathMax(1.0, gridStepPips);
      m_drawVisuals        = drawVisuals && !MQLInfoInteger(MQL_OPTIMIZATION);
      m_lastEvaluatedBar   = 0;
      m_prevBias           = GT_BIAS_NEUTRAL;
      m_lastSignalArrowBar = 0;
      m_cachedData.Reset();
   }

   void ClearVisuals() const
   {
      ObjectsDeleteAll(0, GT_VIS_PREFIX);
   }

   void DrawLevels(const SMarketContext &ctx) const
   {
      if(!m_drawVisuals)
         return;

      DrawHLine(GT_VIS_PREFIX + "EQ50",  ctx.eq50,       C'100,116,139', STYLE_DOT,  "GT EQ50 Equilibrium");
      DrawHLine(GT_VIS_PREFIX + "CRT_H", ctx.crtRefHigh, C'248,113,113', STYLE_DASH, "GT CRT Ref High");
      DrawHLine(GT_VIS_PREFIX + "CRT_L", ctx.crtRefLow,  C'52,211,153',  STYLE_DASH, "GT CRT Ref Low");
   }

   bool Evaluate(const SMarketContext &ctx,
                 const CPipConverter &pipConv,
                 SIndicatorData &outData)
   {
      MqlRates barArr[];
      ArraySetAsSeries(barArr, true);
      if(CopyRates(m_symbol, m_tf, m_signalShift, 2, barArr) < 2)
      {
         outData = m_cachedData;
         return m_cachedData.valid;
      }

      MqlRates sigBar = barArr[0];

      if(m_signalShift > 0 && sigBar.time == m_lastEvaluatedBar && m_cachedData.valid)
      {
         outData = m_cachedData;
         return true;
      }

      outData.Reset();
      outData.valid   = true;
      outData.barTime = sigBar.time;

      ENUM_GT_BIAS curBias      = DetermineBias(ctx);
      outData.bias              = curBias;
      outData.prevBias          = m_prevBias;
      outData.biasChangedToBull = (curBias == GT_BIAS_BULLISH && m_prevBias != GT_BIAS_BULLISH);
      outData.biasChangedToBear = (curBias == GT_BIAS_BEARISH && m_prevBias != GT_BIAS_BEARISH);

      double range     = MathMax(pipConv.PointSize(), sigBar.high - sigBar.low);
      double lowerWick = MathMin(sigBar.open, sigBar.close) - sigBar.low;
      double upperWick = sigBar.high - MathMax(sigBar.open, sigBar.close);

      // KONFIRMASI CANDLE: candle sinyal harus bullish (close>open) ATAU punya sumbu bawah panjang
      // (>=45% range) dengan close di setengah atas -> tanda penolakan harga ke bawah (rejection).
      bool bullCandleConfirm = (sigBar.close > sigBar.open) ||
                               (lowerWick >= range * 0.45 && sigBar.close >= sigBar.low + range * 0.50);
      bool bearCandleConfirm = (sigBar.close < sigBar.open) ||
                               (upperWick >= range * 0.45 && sigBar.close <= sigBar.high - range * 0.50);

      //================================================================
      // ALASAN ENTRY BUY: skor = KATALIS (pemicu) + ZONA (lokasi) + KILLZONE (waktu)
      // Setiap token pada bullReason muncul di komentar order & log: mis. "CRT_Bull+xSSL+CHoCH+OTE"
      //================================================================
      int    bullScore    = 0;
      bool   bullCatalyst = false;
      bool   bullZoneOK   = false;
      string bullReason   = "";

      // ---- KATALIS BUY (sapuan likuiditas sell-side / pergeseran struktur ke atas) ----
      if(ctx.crtBull)                            { bullScore += 3; bullCatalyst = true; AppendToken(bullReason, "CRT_Bull"); } // CRT: low candle ref disapu lalu close kembali dalam range
      if(ctx.xSSL)                               { bullScore += 3; bullCatalyst = true; AppendToken(bullReason, "xSSL"); }     // External sell-side liquidity tersapu (stop hunt di bawah swing low eksternal)
      if(ctx.idmSweptBull)                       { bullScore += 3; bullCatalyst = true; AppendToken(bullReason, "IDM"); }      // Inducement internal tersapu (jebakan sebelum naik)
      if(ctx.chochBull)                          { bullScore += 3; bullCatalyst = true; AppendToken(bullReason, "CHoCH"); }    // Change of Character bullish: tren turun patah
      if(ctx.bosBull)                            { bullScore += 2; bullCatalyst = true; AppendToken(bullReason, "BOS"); }      // Break of Structure bullish: tren naik berlanjut
      if(ctx.ichochBull)                         { bullScore += 2; bullCatalyst = true; AppendToken(bullReason, "iCHoCH"); }   // CHoCH internal bullish (konfirmasi awal)
      if(ctx.ibosBull)                           { bullScore += 1; bullCatalyst = true; AppendToken(bullReason, "iBOS"); }     // BOS internal bullish
      if(ctx.eqlSweptBull)                       { bullScore += 2; bullCatalyst = true; AppendToken(bullReason, "EQL"); }      // Equal Lows tersapu
      if(ctx.pdlSweptBull || ctx.pwlSweptBull)   { bullScore += 2; bullCatalyst = true; AppendToken(bullReason, "PDL/PWL"); }  // Low hari/minggu sebelumnya tersapu
      if(ctx.sweepBull && !ctx.xSSL)             { bullScore += 1; bullCatalyst = true; AppendToken(bullReason, "Sweep"); }    // Sapuan umum (bukan xSSL, agar tidak dihitung ganda)

      // ---- ZONA BUY (lokasi entry berkualitas: area demand / diskon) ----
      if(ctx.atBullOB)                           { bullScore += 3; bullZoneOK = true;   AppendToken(bullReason, "BullOB"); }   // Harga berada DI DALAM Bullish Order Block
      else if(ctx.bullOBValid)                   { bullScore += 1; bullZoneOK = true;   }                                       // OB ada tapi harga belum di dalamnya (tanpa token)
      if(ctx.bullIFVG)                           { bullScore += 2; bullZoneOK = true;   AppendToken(bullReason, "IFVG"); }     // Inversion FVG bullish
      if(ctx.bullFVGValid)                       { bullScore += 2; bullZoneOK = true;   AppendToken(bullReason, "FVG"); }      // Bullish FVG aktif (imbalance belum terisi)
      if(ctx.bullBreakerActive)                  { bullScore += 2; bullZoneOK = true;   AppendToken(bullReason, "Breaker"); }  // Breaker block bullish
      if(ctx.inBullOTE)                          { bullScore += 2; bullZoneOK = true;   AppendToken(bullReason, "OTE"); }      // Optimal Trade Entry (Fib 0.618-0.786)
      else if(ctx.inDiscount)                    { bullScore += 1; bullZoneOK = true;   AppendToken(bullReason, "Disc"); }     // Setengah bawah dealing range (diskon)
      if(ctx.bullMB || ctx.bullVI || ctx.bullVoid){ bullScore += 1; bullZoneOK = true;  }                                      // Mitigation Block / Volume Imbalance / Liquidity Void (tanpa token)
      if(ctx.inKillZone)                         { bullScore += 1; AppendToken(bullReason, "KZ"); }                             // Bonus waktu: sesi likuid (London / NY)

      //================================================================
      // ALASAN ENTRY SELL: cermin dari BUY (sapuan buy-side / struktur turun / zona premium)
      //================================================================
      int    bearScore    = 0;
      bool   bearCatalyst = false;
      bool   bearZoneOK   = false;
      string bearReason   = "";

      // ---- KATALIS SELL ----
      if(ctx.crtBear)                            { bearScore += 3; bearCatalyst = true; AppendToken(bearReason, "CRT_Bear"); } // CRT: high candle ref disapu lalu close kembali dalam range
      if(ctx.xBSL)                               { bearScore += 3; bearCatalyst = true; AppendToken(bearReason, "xBSL"); }     // External buy-side liquidity tersapu
      if(ctx.idmSweptBear)                       { bearScore += 3; bearCatalyst = true; AppendToken(bearReason, "IDM"); }      // Inducement internal tersapu (jebakan sebelum turun)
      if(ctx.chochBear)                          { bearScore += 3; bearCatalyst = true; AppendToken(bearReason, "CHoCH"); }    // CHoCH bearish: tren naik patah
      if(ctx.bosBear)                            { bearScore += 2; bearCatalyst = true; AppendToken(bearReason, "BOS"); }      // BOS bearish: tren turun berlanjut
      if(ctx.ichochBear)                         { bearScore += 2; bearCatalyst = true; AppendToken(bearReason, "iCHoCH"); }   // CHoCH internal bearish
      if(ctx.ibosBear)                           { bearScore += 1; bearCatalyst = true; AppendToken(bearReason, "iBOS"); }     // BOS internal bearish
      if(ctx.eqhSweptBear)                       { bearScore += 2; bearCatalyst = true; AppendToken(bearReason, "EQH"); }      // Equal Highs tersapu
      if(ctx.pdhSweptBear || ctx.pwhSweptBear)   { bearScore += 2; bearCatalyst = true; AppendToken(bearReason, "PDH/PWH"); }  // High hari/minggu sebelumnya tersapu
      if(ctx.sweepBear && !ctx.xBSL)             { bearScore += 1; bearCatalyst = true; AppendToken(bearReason, "Sweep"); }    // Sapuan umum

      // ---- ZONA SELL (area supply / premium) ----
      if(ctx.atBearOB)                           { bearScore += 3; bearZoneOK = true;   AppendToken(bearReason, "BearOB"); }   // Harga di dalam Bearish Order Block
      else if(ctx.bearOBValid)                   { bearScore += 1; bearZoneOK = true;   }
      if(ctx.bearIFVG)                           { bearScore += 2; bearZoneOK = true;   AppendToken(bearReason, "IFVG"); }     // Inversion FVG bearish
      if(ctx.bearFVGValid)                       { bearScore += 2; bearZoneOK = true;   AppendToken(bearReason, "FVG"); }      // Bearish FVG aktif
      if(ctx.bearBreakerActive)                  { bearScore += 2; bearZoneOK = true;   AppendToken(bearReason, "Breaker"); }  // Breaker block bearish
      if(ctx.inBearOTE)                          { bearScore += 2; bearZoneOK = true;   AppendToken(bearReason, "OTE"); }      // OTE bearish (Fib 0.618-0.786 dari bawah)
      else if(ctx.inPremium)                     { bearScore += 1; bearZoneOK = true;   AppendToken(bearReason, "Prem"); }     // Setengah atas dealing range (premium)
      if(ctx.bearMB || ctx.bearVI || ctx.bearVoid){ bearScore += 1; bearZoneOK = true;  }
      if(ctx.inKillZone)                         { bearScore += 1; AppendToken(bearReason, "KZ"); }

      //================================================================
      // KEPUTUSAN ENTRY: bias searah + konfirmasi candle + skor minimum
      //   Konservatif : skor>=8 DAN ada katalis DAN ada zona
      //   Seimbang    : skor>=5 DAN ada katalis
      //   Agresif     : skor>=3 saja
      //================================================================
      bool buyTrigger  = false;
      bool sellTrigger = false;

      int minReqScore = 5;
      if(m_sensitivity == GT_SENS_CONSERVATIVE) minReqScore = 8;
      else if(m_sensitivity == GT_SENS_AGGRESSIVE) minReqScore = 3;

      if(curBias == GT_BIAS_BULLISH && bullCandleConfirm)
      {
         if(m_sensitivity == GT_SENS_CONSERVATIVE)
            buyTrigger = (bullScore >= minReqScore && bullCatalyst && bullZoneOK);
         else if(m_sensitivity == GT_SENS_BALANCED)
            buyTrigger = (bullScore >= minReqScore && bullCatalyst);
         else
            buyTrigger = (bullScore >= minReqScore);
      }

      if(curBias == GT_BIAS_BEARISH && bearCandleConfirm)
      {
         if(m_sensitivity == GT_SENS_CONSERVATIVE)
            sellTrigger = (bearScore >= minReqScore && bearCatalyst && bearZoneOK);
         else if(m_sensitivity == GT_SENS_BALANCED)
            sellTrigger = (bearScore >= minReqScore && bearCatalyst);
         else
            sellTrigger = (bearScore >= minReqScore);
      }

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(ask <= 0.0) ask = sigBar.close;
      if(bid <= 0.0) bid = sigBar.close;

      // Sinyal konflik (BUY & SELL sekaligus) dibuang: tidak ada entry
      if(buyTrigger && !sellTrigger)
      {
         outData.buySignal    = true;
         outData.buySignalRaw = sigBar.low;
         // Format "BUY(skor): token+token" -> bagian setelah ": " dipakai sebagai komentar order
         outData.signalReason = StringFormat("BUY(%d): %s", bullScore, bullReason);
         ComputeStructuralSLTP(true, ask, sigBar, ctx, pipConv, outData.buySL, outData.buyTP);

         if(m_drawVisuals && sigBar.time != m_lastSignalArrowBar)
         {
            DrawSignalArrow(sigBar.time, sigBar.low - pipConv.PipsToPrice(2.0), true, outData.signalReason);
            m_lastSignalArrowBar = sigBar.time;
         }
      }
      else if(sellTrigger && !buyTrigger)
      {
         outData.sellSignal    = true;
         outData.sellSignalRaw = sigBar.high;
         outData.signalReason  = StringFormat("SELL(%d): %s", bearScore, bearReason);
         ComputeStructuralSLTP(false, bid, sigBar, ctx, pipConv, outData.sellSL, outData.sellTP);

         if(m_drawVisuals && sigBar.time != m_lastSignalArrowBar)
         {
            DrawSignalArrow(sigBar.time, sigBar.high + pipConv.PipsToPrice(2.0), false, outData.signalReason);
            m_lastSignalArrowBar = sigBar.time;
         }
      }
      else
      {
         outData.signalReason = (curBias == GT_BIAS_BULLISH)
                                ? StringFormat("Wait BUY (Skor %d/%d)", bullScore, minReqScore)
                                : ((curBias == GT_BIAS_BEARISH)
                                   ? StringFormat("Wait SELL (Skor %d/%d)", bearScore, minReqScore)
                                   : "Bias Netral (Menunggu Struktur)");
      }

      if(m_drawVisuals)
         DrawLevels(ctx);

      m_prevBias         = curBias;
      m_lastEvaluatedBar = sigBar.time;
      m_cachedData       = outData;
      return true;
   }
};

//--- Buffer index definitions (ICT_SMC_CRT contract)
#define GT_BUF_BUY_SIGNAL   0
#define GT_BUF_SELL_SIGNAL  1
#define GT_BUF_BUY_SL       2
#define GT_BUF_BUY_TP       3
#define GT_BUF_SELL_SL      4
#define GT_BUF_SELL_TP      5
#define GT_BUF_BIAS         6

//+------------------------------------------------------------------+
//| CIndicatorBridge                                                 |
//+------------------------------------------------------------------+
class CIndicatorBridge
{
private:
   ENUM_GT_SIGNAL_SOURCE m_sourceMode;
   CInternalSignalEngine m_internal;

   int                   m_handle;
   string                m_symbol;
   ENUM_TIMEFRAMES       m_timeframe;
   string                m_indName;
   int                   m_signalShift;
   SIndicatorData        m_lastData;
   string                m_lastError;

   bool IsActiveSignalValue(const double val) const
   {
      if(val == EMPTY_VALUE)            return false;
      if(!MathIsValidNumber(val))       return false;
      if(MathAbs(val) < 1e-10)          return false;
      if(val >= 1e100 || val <= -1e100) return false;
      return true;
   }

   bool IsValidPriceValue(const double val) const
   {
      if(val == EMPTY_VALUE)            return false;
      if(!MathIsValidNumber(val))       return false;
      if(val <= 0.0 || val >= 1e100)    return false;
      return true;
   }

   ENUM_GT_BIAS DecodeBias(const double rawVal) const
   {
      if(rawVal == EMPTY_VALUE || !MathIsValidNumber(rawVal))
         return GT_BIAS_NEUTRAL;
      if(rawVal > 0.5)  return GT_BIAS_BULLISH;
      if(rawVal < -0.5) return GT_BIAS_BEARISH;
      return GT_BIAS_NEUTRAL;
   }

public:
   CIndicatorBridge()
   {
      m_sourceMode  = GT_SRC_INTERNAL_ALL_IN_ONE;
      m_handle      = INVALID_HANDLE;
      m_symbol      = _Symbol;
      m_timeframe   = PERIOD_CURRENT;
      m_indName     = "ICT_SMC_CRT";
      m_signalShift = 1;
      m_lastError   = "";
      m_lastData.Reset();
   }

   ~CIndicatorBridge()
   {
      Deinit();
   }

   bool Init(const ENUM_GT_SIGNAL_SOURCE sourceMode,
             const string symbol,
             const ENUM_TIMEFRAMES tf,
             const string indicatorName,
             const int signalShift,
             const ENUM_GT_ENTRY_SENSITIVITY sensitivity,
             const double slBufferPips,
             const double defaultSLPips,
             const double targetRR,
             const double gridStepPips,
             const bool drawVisuals)
   {
      Deinit();

      m_sourceMode  = sourceMode;
      m_symbol      = symbol;
      m_timeframe   = tf;
      m_indName     = indicatorName;
      m_signalShift = MathMax(0, signalShift);
      m_lastError   = "";
      m_lastData.Reset();

      if(m_sourceMode == GT_SRC_INTERNAL_ALL_IN_ONE)
      {
         m_internal.Init(m_symbol, m_timeframe, m_signalShift,
                         sensitivity, slBufferPips, defaultSLPips,
                         targetRR, gridStepPips, drawVisuals);
         PrintFormat("[GT Recovery Engine] Mode ALL-IN-ONE Internal ICT+SMC+CRT aktif (TF=%s, Shift=%d).",
                     EnumToString(m_timeframe), m_signalShift);
         return true;
      }

      ResetLastError();
      m_handle = iCustom(m_symbol, m_timeframe, m_indName);
      if(m_handle == INVALID_HANDLE)
      {
         int err = GetLastError();
         m_lastError = StringFormat("Gagal memuat indikator eksternal '%s' via iCustom (Error %d). Pastikan file MQL5\\Indicators\\%s.ex5 tersedia atau pilih Mode All-in-One.",
                                    m_indName, err, m_indName);
         Print("[GT Recovery Engine][ERROR] ", m_lastError);
         return false;
      }

      PrintFormat("[GT Recovery Engine] Indikator eksternal '%s' dimuat (Handle=%d, TF=%s, Shift=%d).",
                  m_indName, m_handle, EnumToString(m_timeframe), m_signalShift);
      return true;
   }

   void Deinit()
   {
      if(m_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_handle);
         m_handle = INVALID_HANDLE;
      }
      m_internal.ClearVisuals();
   }

   ENUM_GT_SIGNAL_SOURCE SourceMode() const { return m_sourceMode; }
   string GetSourceLabel() const
   {
      return (m_sourceMode == GT_SRC_INTERNAL_ALL_IN_ONE) ? "ALL-IN-ONE" : "iCustom";
   }

   bool IsReady() const
   {
      if(m_sourceMode == GT_SRC_INTERNAL_ALL_IN_ONE)
         return true;
      return (m_handle != INVALID_HANDLE);
   }

   string         LastError()   const { return m_lastError; }
   SIndicatorData GetLastData() const { return m_lastData; }

   bool Refresh(const SMarketContext &ctx,
                const CPipConverter &pipConv,
                SIndicatorData &outData)
   {
      if(m_sourceMode == GT_SRC_INTERNAL_ALL_IN_ONE)
      {
         bool ok = m_internal.Evaluate(ctx, pipConv, outData);
         if(ok)
            m_lastData = outData;
         return ok;
      }

      outData.Reset();

      if(m_handle == INVALID_HANDLE)
      {
         m_lastError = "Handle indikator ICT_SMC_CRT tidak valid.";
         return false;
      }

      int calculated = BarsCalculated(m_handle);
      if(calculated < m_signalShift + 3)
         return false;

      int copyCount = 2;
      double bufBuySig[];
      double bufSellSig[];
      double bufBuySL[];
      double bufBuyTP[];
      double bufSellSL[];
      double bufSellTP[];
      double bufBias[];

      ArraySetAsSeries(bufBuySig,  true);
      ArraySetAsSeries(bufSellSig, true);
      ArraySetAsSeries(bufBuySL,   true);
      ArraySetAsSeries(bufBuyTP,   true);
      ArraySetAsSeries(bufSellSL,  true);
      ArraySetAsSeries(bufSellTP,  true);
      ArraySetAsSeries(bufBias,    true);

      if(CopyBuffer(m_handle, GT_BUF_BUY_SIGNAL,  m_signalShift, copyCount, bufBuySig)  < copyCount) return false;
      if(CopyBuffer(m_handle, GT_BUF_SELL_SIGNAL, m_signalShift, copyCount, bufSellSig) < copyCount) return false;
      if(CopyBuffer(m_handle, GT_BUF_BUY_SL,      m_signalShift, copyCount, bufBuySL)   < copyCount) return false;
      if(CopyBuffer(m_handle, GT_BUF_BUY_TP,      m_signalShift, copyCount, bufBuyTP)   < copyCount) return false;
      if(CopyBuffer(m_handle, GT_BUF_SELL_SL,     m_signalShift, copyCount, bufSellSL)  < copyCount) return false;
      if(CopyBuffer(m_handle, GT_BUF_SELL_TP,     m_signalShift, copyCount, bufSellTP)  < copyCount) return false;
      if(CopyBuffer(m_handle, GT_BUF_BIAS,        m_signalShift, copyCount, bufBias)    < copyCount) return false;

      datetime barTimes[];
      ArraySetAsSeries(barTimes, true);
      if(CopyTime(m_symbol, m_timeframe, m_signalShift, 1, barTimes) < 1)
         return false;

      outData.valid         = true;
      outData.barTime       = barTimes[0];
      outData.buySignalRaw  = bufBuySig[0];
      outData.sellSignalRaw = bufSellSig[0];
      outData.buySignal     = IsActiveSignalValue(bufBuySig[0]);
      outData.sellSignal    = IsActiveSignalValue(bufSellSig[0]);
      outData.buySL         = IsValidPriceValue(bufBuySL[0])  ? bufBuySL[0]  : 0.0;
      outData.buyTP         = IsValidPriceValue(bufBuyTP[0])  ? bufBuyTP[0]  : 0.0;
      outData.sellSL        = IsValidPriceValue(bufSellSL[0]) ? bufSellSL[0] : 0.0;
      outData.sellTP        = IsValidPriceValue(bufSellTP[0]) ? bufSellTP[0] : 0.0;
      outData.bias          = DecodeBias(bufBias[0]);
      outData.prevBias      = DecodeBias(bufBias[1]);

      outData.biasChangedToBull = (outData.bias == GT_BIAS_BULLISH && outData.prevBias != GT_BIAS_BULLISH);
      outData.biasChangedToBear = (outData.bias == GT_BIAS_BEARISH && outData.prevBias != GT_BIAS_BEARISH);
      // Mode iCustom: indikator eksternal tidak membocorkan alasan detail, hanya arah sinyal
      outData.signalReason      = outData.buySignal ? "iCustom BUY"
                                : (outData.sellSignal ? "iCustom SELL" : "iCustom Standby");

      m_lastData = outData;
      return true;
   }

   //--- ENTRY BUY sah: sinyal BUY aktif + bias BULLISH + tidak ada sinyal SELL bersamaan
   bool IsValidBuyEntry(const SIndicatorData &data) const
   {
      if(!data.valid) return false;
      return (data.buySignal && data.bias == GT_BIAS_BULLISH && !data.sellSignal);
   }

   //--- ENTRY SELL sah: sinyal SELL aktif + bias BEARISH + tidak ada sinyal BUY bersamaan
   bool IsValidSellEntry(const SIndicatorData &data) const
   {
      if(!data.valid) return false;
      return (data.sellSignal && data.bias == GT_BIAS_BEARISH && !data.buySignal);
   }
};

//+------------------------------------------------------------------+
//| CProbabilityEngine                                               |
//+------------------------------------------------------------------+
class CProbabilityEngine
{
private:
   SScoreWeights        m_weights;
   SProbabilityDecision m_lastDecision;

   void AppendFactor(string &list, const string token) const
   {
      if(token == "") return;
      if(list == "" || list == "-")
         list = token;
      else
         list += " + " + token;
   }

public:
   CProbabilityEngine()
   {
      ZeroMemory(m_weights);
      m_lastDecision.Reset();
   }

   void Configure(const SScoreWeights &weights)
   {
      m_weights = weights;
   }

   SProbabilityDecision GetLastDecision() const
   {
      return m_lastDecision;
   }

   //--- Menilai posisi berarah currentDir: apakah pasar kini cenderung BALIK ARAH (Flip)
   //    atau masih sejalan (Martingale Klasik). Hasil ini adalah ALASAN entry recovery.
   SProbabilityDecision Evaluate(const ENUM_GT_DIR currentDir,
                                 const SMarketContext &ctx,
                                 const SIndicatorData &ind)
   {
      SProbabilityDecision dec;
      dec.Reset();
      dec.evaluatedForDir = currentDir;
      dec.threshold       = m_weights.flipThreshold;

      if(currentDir == GT_DIR_NONE)
      {
         m_lastDecision = dec;
         return dec;
      }

      bool isBuyPos = (currentDir == GT_DIR_BUY);

      // ---- Faktor REVERSAL: sinyal yang MELAWAN arah posisi saat ini ----
      bool revIDM        = isBuyPos ? ctx.idmSweptBear      : ctx.idmSweptBull;   // Inducement lawan tersapu
      bool revExtLiq     = isBuyPos ? ctx.xBSL              : ctx.xSSL;           // Likuiditas eksternal lawan tersapu
      string extLiqLabel = isBuyPos ? "xBSL"                : "xSSL";
      int  wExtLiq       = isBuyPos ? m_weights.wXBSL       : m_weights.wXSSL;

      bool revCHoCH      = isBuyPos ? ctx.chochBear         : ctx.chochBull;      // CHoCH lawan arah (struktur patah)
      bool revCRT        = isBuyPos ? ctx.crtBear           : ctx.crtBull;        // CRT reversal
      bool revIFVG       = isBuyPos ? ctx.bearIFVG          : ctx.bullIFVG;       // IFVG lawan arah
      bool revFVG        = isBuyPos ? ctx.bearFVGValid      : ctx.bullFVGValid;   // FVG lawan arah aktif
      bool revOB         = isBuyPos ? (ctx.bearOBValid && ctx.atBearOB) : (ctx.bullOBValid && ctx.atBullOB); // Harga di OB lawan
      bool revBreaker    = isBuyPos ? ctx.bearBreakerActive : ctx.bullBreakerActive;
      bool revBOS        = isBuyPos ? ctx.bosBear           : ctx.bosBull;        // BOS lawan arah
      bool revICHoCH     = isBuyPos ? ctx.ichochBear        : ctx.ichochBull;
      bool revIBOS       = isBuyPos ? ctx.ibosBear          : ctx.ibosBull;
      bool revOTE        = isBuyPos ? ctx.inBearOTE         : ctx.inBullOTE;
      bool revZoneFav    = isBuyPos ? ctx.inPremium         : ctx.inDiscount;     // Posisi BUY di premium / SELL di discount = zona buruk
      string revZoneLbl  = isBuyPos ? "Premium"             : "Discount";
      int  wRevZone      = isBuyPos ? m_weights.wPremium    : m_weights.wDiscount;

      bool revSweep      = isBuyPos ? ctx.sweepBear         : ctx.sweepBull;
      bool revEQ         = isBuyPos ? ctx.eqhSweptBear      : ctx.eqlSweptBull;
      bool revMB_VI_Void = isBuyPos ? (ctx.bearMB || ctx.bearVI || ctx.bearVoid)
                                    : (ctx.bullMB || ctx.bullVI || ctx.bullVoid);
      bool revHTFLiq     = isBuyPos ? (ctx.pdhSweptBear || ctx.pwhSweptBear)
                                    : (ctx.pdlSweptBull || ctx.pwlSweptBull);

      // Bias / sinyal indikator berbalik melawan posisi
      bool revIndBias    = false;
      if(ind.valid)
      {
         if(isBuyPos  && (ind.bias == GT_BIAS_BEARISH || ind.sellSignal)) revIndBias = true;
         if(!isBuyPos && (ind.bias == GT_BIAS_BULLISH || ind.buySignal))  revIndBias = true;
      }

      // ---- Faktor KONTINUASI: bukti bahwa arah posisi lama masih sehat ----
      bool noOppCHoCH    = !revCHoCH;
      bool noOppBOS      = !revBOS;
      bool contZoneFav   = isBuyPos ? ctx.inDiscount        : ctx.inPremium;
      bool contOTE       = isBuyPos ? ctx.inBullOTE         : ctx.inBearOTE;
      bool contOBValid   = isBuyPos ? ctx.bullOBValid       : ctx.bearOBValid;
      bool contFVGValid  = isBuyPos ? ctx.bullFVGValid      : ctx.bearFVGValid;
      bool contIndAligned = false;
      if(ind.valid)
      {
         if(isBuyPos  && ind.bias == GT_BIAS_BULLISH) contIndAligned = true;
         if(!isBuyPos && ind.bias == GT_BIAS_BEARISH) contIndAligned = true;
      }

      // Struktur "utuh" = belum ada CHoCH/BOS lawan
      dec.structureIntact = (noOppCHoCH && noOppBOS);

      // Hitung jumlah sinyal per tier (dipakai mode hierarki & tampilan panel)
      int t1 = 0, t2 = 0, t3 = 0;

      if(revIDM)    t1++;
      if(revExtLiq) t1++;
      if(revCHoCH)  t1++;
      if(revCRT)    t1++;

      bool tier2ComboLiqChoch = (revExtLiq && revCHoCH);   // Kombo kuat: sapuan likuiditas + CHoCH
      if(tier2ComboLiqChoch) t2++;
      if(revIFVG)            t2++;

      if(revBOS)    t3++;
      if(revIBOS)   t3++;
      if(revICHoCH) t3++;

      dec.tier1Count = t1;
      dec.tier2Count = t2;
      dec.tier3Count = t3;

      if(t1 > 0)      dec.highestTier = GT_TIER_1;
      else if(t2 > 0) dec.highestTier = GT_TIER_2;
      else if(t3 > 0) dec.highestTier = GT_TIER_3;
      else            dec.highestTier = GT_TIER_NONE;

      // ---- Akumulasi SKOR REVERSAL (bobot dari input) ----
      int revScore = 0;
      string revList = "";

      if(revIDM && m_weights.wIDM > 0)
      {
         revScore += m_weights.wIDM;
         AppendFactor(revList, StringFormat("IDM(+%d)", m_weights.wIDM));
      }
      if(revExtLiq && wExtLiq > 0)
      {
         revScore += wExtLiq;
         AppendFactor(revList, StringFormat("%s(+%d)", extLiqLabel, wExtLiq));
      }
      if(revCHoCH && m_weights.wCHoCH > 0)
      {
         revScore += m_weights.wCHoCH;
         AppendFactor(revList, StringFormat("%sCHoCH(+%d)", isBuyPos ? "Bear" : "Bull", m_weights.wCHoCH));
      }
      if(revCRT && m_weights.wCRT > 0)
      {
         revScore += m_weights.wCRT;
         AppendFactor(revList, StringFormat("CRT%s(+%d)", isBuyPos ? "Bear" : "Bull", m_weights.wCRT));
      }
      if(revIFVG && m_weights.wIFVG > 0)
      {
         revScore += m_weights.wIFVG;
         AppendFactor(revList, StringFormat("IFVG(+%d)", m_weights.wIFVG));
      }
      if(revFVG && m_weights.wFVG > 0)
      {
         revScore += m_weights.wFVG;
         AppendFactor(revList, StringFormat("FVG(+%d)", m_weights.wFVG));
      }
      if(revOB && m_weights.wOB > 0)
      {
         revScore += m_weights.wOB;
         AppendFactor(revList, StringFormat("OB(+%d)", m_weights.wOB));
      }
      if(revBOS && m_weights.wBOS > 0)
      {
         revScore += m_weights.wBOS;
         AppendFactor(revList, StringFormat("BOS(+%d)", m_weights.wBOS));
      }
      if(revICHoCH && m_weights.wICHoCH > 0)
      {
         revScore += m_weights.wICHoCH;
         AppendFactor(revList, StringFormat("iCHoCH(+%d)", m_weights.wICHoCH));
      }
      if(revIBOS && m_weights.wIBOS > 0)
      {
         revScore += m_weights.wIBOS;
         AppendFactor(revList, StringFormat("iBOS(+%d)", m_weights.wIBOS));
      }
      if(revOTE && m_weights.wOTE > 0)
      {
         revScore += m_weights.wOTE;
         AppendFactor(revList, StringFormat("OTE(+%d)", m_weights.wOTE));
      }
      if(revZoneFav && wRevZone > 0)
      {
         revScore += wRevZone;
         AppendFactor(revList, StringFormat("%s(+%d)", revZoneLbl, wRevZone));
      }

      // Sweep umum tidak dihitung ganda jika xSSL/xBSL atau IDM sudah masuk skor
      if(revSweep && !revExtLiq && !revIDM && m_weights.wSweep > 0)
      {
         revScore += m_weights.wSweep;
         AppendFactor(revList, StringFormat("Sweep(+%d)", m_weights.wSweep));
      }
      if(revEQ && m_weights.wEQH_EQL > 0)
      {
         revScore += m_weights.wEQH_EQL;
         AppendFactor(revList, StringFormat("%s(+%d)", isBuyPos ? "EQH" : "EQL", m_weights.wEQH_EQL));
      }
      if(revBreaker && m_weights.wBreaker > 0)
      {
         revScore += m_weights.wBreaker;
         AppendFactor(revList, StringFormat("Breaker(+%d)", m_weights.wBreaker));
      }
      if(revMB_VI_Void && m_weights.wMB_VI_Void > 0)
      {
         revScore += m_weights.wMB_VI_Void;
         AppendFactor(revList, StringFormat("MB/VI/Void(+%d)", m_weights.wMB_VI_Void));
      }
      if(revHTFLiq && m_weights.wHTFLiq > 0)
      {
         revScore += m_weights.wHTFLiq;
         AppendFactor(revList, StringFormat("PD/PW_Liq(+%d)", m_weights.wHTFLiq));
      }
      // Bonus KillZone hanya jika sudah ada minimal 1 faktor reversal (tidak berdiri sendiri)
      if(ctx.inKillZone && revScore > 0 && m_weights.wKillZone > 0)
      {
         revScore += m_weights.wKillZone;
         AppendFactor(revList, StringFormat("KZ(+%d)", m_weights.wKillZone));
      }
      if(revIndBias && m_weights.wIndBiasFlip > 0)
      {
         revScore += m_weights.wIndBiasFlip;
         AppendFactor(revList, StringFormat("IndBiasFlip(+%d)", m_weights.wIndBiasFlip));
      }

      dec.reversalScore         = revScore;
      dec.activeReversalFactors = (revList == "") ? "Tidak ada sinyal reversal" : revList;

      int contScore = 0;
      string contList = "";

      if(noOppCHoCH)     { contScore += 3; AppendFactor(contList, "NoOppCHoCH"); }
      if(noOppBOS)       { contScore += 2; AppendFactor(contList, "NoOppBOS"); }
      if(contZoneFav)    { contScore += 2; AppendFactor(contList, isBuyPos ? "Discount" : "Premium"); }
      if(contOTE)        { contScore += 2; AppendFactor(contList, "OTE"); }
      if(contOBValid)    { contScore += 2; AppendFactor(contList, isBuyPos ? "BullOB" : "BearOB"); }
      if(contFVGValid)   { contScore += 2; AppendFactor(contList, isBuyPos ? "BullFVG" : "BearFVG"); }
      if(contIndAligned) { contScore += 3; AppendFactor(contList, "IndBiasAligned"); }

      dec.continuationScore         = contScore;
      dec.activeContinuationFactors = (contList == "") ? "Struktur lemah" : contList;

      //================================================================
      // KEPUTUSAN FLIP vs KLASIK
      //   Mode Skor    : FLIP jika skor reversal > threshold
      //   Mode Hierarki: FLIP jika salah satu kombinasi tier terpenuhi
      //================================================================
      bool flipActivated = false;

      if(m_weights.enabled)
      {
         flipActivated = (dec.reversalScore > m_weights.flipThreshold);
      }
      else
      {
         if(tier2ComboLiqChoch)
            flipActivated = true;                                                       // Sapuan likuiditas + CHoCH
         else if(revIDM && (revExtLiq || revCHoCH || revCRT || revIFVG || revIndBias))
            flipActivated = true;                                                       // IDM + konfirmasi lain
         else if(t1 >= 2)
            flipActivated = true;                                                       // Dua sinyal Tier 1
         else if(t1 >= 1 && t2 >= 1 && t3 >= 1)
            flipActivated = true;                                                       // Satu sinyal di tiap tier
         else if(revIndBias && (t1 >= 1 || t2 >= 1))
            flipActivated = true;                                                       // Bias indikator berbalik + Tier 1/2
      }

      if(flipActivated)
      {
         dec.mode           = GT_REC_FLIP;
         dec.recommendedDir = isBuyPos ? GT_DIR_SELL : GT_DIR_BUY;
         dec.allowExecution = true;
         dec.summaryReason  = StringFormat("FLIP -> %s | Skor=%d > %d | %s | %s",
                                           GT_DirToString(dec.recommendedDir),
                                           dec.reversalScore,
                                           dec.threshold,
                                           GT_TierToString(dec.highestTier),
                                           dec.activeReversalFactors);
      }
      else
      {
         dec.mode           = GT_REC_CLASSIC;
         dec.recommendedDir = currentDir;
         dec.allowExecution = (!m_weights.requireIntactStructureForClassic || dec.structureIntact);
         if(dec.allowExecution)
         {
            dec.summaryReason = StringFormat("KLASIK -> %s | SkorRev=%d <= %d | Kont=%d (%s)",
                                             GT_DirToString(dec.recommendedDir),
                                             dec.reversalScore,
                                             dec.threshold,
                                             dec.continuationScore,
                                             dec.activeContinuationFactors);
         }
         else
         {
            dec.summaryReason = StringFormat("TAHAN KLASIK (Struktur terganggu: Opp CHoCH/BOS, SkorRev=%d <= %d)",
                                             dec.reversalScore,
                                             dec.threshold);
         }
      }

      m_lastDecision = dec;
      return dec;
   }
};

//+------------------------------------------------------------------+
//| CSafetyManager  (v1.32: Daily DD Resume-On-Signal)               |
//+------------------------------------------------------------------+
class CSafetyManager
{
private:
   string            m_symbol;
   long              m_magic;

   int               m_maxLevel;
   ENUM_GT_LOSS_MODE m_floatingLossMode;
   double            m_maxFloatingLoss;
   double            m_maxDailyDDPct;
   int               m_maxOpenPositions;
   bool              m_emergencyInput;
   bool              m_emergencyManual;
   bool              m_closeAllOnEmergency;
   bool              m_alertsEnabled;

   datetime          m_currentDay;
   double            m_dayStartBalance;
   bool              m_dailyDDLatched;
   string            m_lastAlertedReason;

   //--- v1.32: Resume DD saat sinyal berikutnya
   bool              m_ddResumeOnSignal;
   int               m_maxDDRearmPerDay;   // 0 = tanpa batas
   int               m_ddRearmCountToday;

   SSafetyStatus     m_status;

   datetime GetDayFloor(const datetime t) const
   {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      dt.hour = 0;
      dt.min  = 0;
      dt.sec  = 0;
      return StructToTime(dt);
   }

   void NotifyBreach(const string reason)
   {
      if(reason == m_lastAlertedReason)
         return;
      m_lastAlertedReason = reason;

      string msg = "[GT Recovery Engine][SAFETY HALT] " + reason;
      Print(msg);
      if(m_alertsEnabled && !MQLInfoInteger(MQL_OPTIMIZATION))
         Alert(msg);
   }

public:
   CSafetyManager()
   {
      m_symbol              = _Symbol;
      m_magic               = 0;
      m_maxLevel            = 5;
      m_floatingLossMode    = GT_LOSS_PERCENT;
      m_maxFloatingLoss     = 10.0;
      m_maxDailyDDPct       = 5.0;
      m_maxOpenPositions    = 6;
      m_emergencyInput      = false;
      m_emergencyManual     = false;
      m_closeAllOnEmergency = false;
      m_alertsEnabled       = true;
      m_currentDay          = 0;
      m_dayStartBalance     = 0.0;
      m_dailyDDLatched      = false;
      m_lastAlertedReason   = "";
      m_ddResumeOnSignal    = true;
      m_maxDDRearmPerDay    = 0;
      m_ddRearmCountToday   = 0;
      m_status.Reset();
   }

   void Init(const string symbol,
             const long magic,
             const int maxLevel,
             const ENUM_GT_LOSS_MODE floatingLossMode,
             const double maxFloatingLoss,
             const double maxDailyDDPct,
             const int maxOpenPositions,
             const bool emergencyStop,
             const bool closeAllOnEmergency,
             const bool alertsEnabled)
   {
      m_symbol              = symbol;
      m_magic               = magic;
      m_maxLevel            = maxLevel;
      m_floatingLossMode    = floatingLossMode;
      m_maxFloatingLoss     = MathMax(0.0, maxFloatingLoss);
      m_maxDailyDDPct       = MathMax(0.0, maxDailyDDPct);
      m_maxOpenPositions    = MathMax(1, maxOpenPositions);
      m_emergencyInput      = emergencyStop;
      m_emergencyManual     = false;
      m_closeAllOnEmergency = closeAllOnEmergency;
      m_alertsEnabled       = alertsEnabled;
      m_dailyDDLatched      = false;
      m_lastAlertedReason   = "";
      m_ddRearmCountToday   = 0;

      m_currentDay      = GetDayFloor(TimeCurrent());
      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_status.Reset();
      m_status.dayStartBalance = m_dayStartBalance;
   }

   //--- v1.32: konfigurasi mode resume DD
   void ConfigureDDResume(const bool resumeOnSignal, const int maxRearmPerDay)
   {
      m_ddResumeOnSignal = resumeOnSignal;
      m_maxDDRearmPerDay = MathMax(0, maxRearmPerDay);
   }

   void TriggerManualEmergency(const bool active)
   {
      m_emergencyManual = active;
      if(!active)
      {
         m_dailyDDLatched    = false;
         m_lastAlertedReason = "";
         //--- Rebase baseline DD ke equity saat resume manual (agar latch tidak langsung terpasang lagi)
         m_dayStartBalance   = AccountInfoDouble(ACCOUNT_EQUITY);
      }
   }

   bool IsManualEmergencyActive() const { return m_emergencyManual; }
   bool ShouldCloseAllOnEmergency() const { return m_closeAllOnEmergency; }
   SSafetyStatus GetStatus() const { return m_status; }
   int  MaxLevel() const { return m_maxLevel; }
   bool IsDDResumeOnSignal() const { return m_ddResumeOnSignal; }

   //--- v1.32: apakah DD saat ini boleh di-rearm oleh sinyal baru
   bool CanRearmAfterDD() const
   {
      if(!m_ddResumeOnSignal)                 return false;
      if(!m_dailyDDLatched)                   return false;
      if(m_emergencyInput || m_emergencyManual) return false;
      if(m_maxDDRearmPerDay > 0 && m_ddRearmCountToday >= m_maxDDRearmPerDay)
         return false;
      return true;
   }

   //--- v1.32: buka kunci DD & mulai baseline DD baru dari equity saat ini
   void RearmAfterDD()
   {
      m_ddRearmCountToday++;
      m_dailyDDLatched    = false;
      m_dayStartBalance   = AccountInfoDouble(ACCOUNT_EQUITY);
      m_lastAlertedReason = "";
      PrintFormat("[GT Recovery Engine] DD RE-ARM #%d: baseline DD baru = %.2f (Equity). Entry dibuka lagi pada sinyal baru.",
                  m_ddRearmCountToday, m_dayStartBalance);
   }

   void Update(const int currentRecoveryLevel,
               const int openPosCount,
               const double symbolFloatingPL,
               const bool pendingRecovery = false)
   {
      datetime nowDay = GetDayFloor(TimeCurrent());
      if(nowDay != m_currentDay)
      {
         m_currentDay        = nowDay;
         m_dayStartBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
         m_dailyDDLatched    = false;
         m_lastAlertedReason = "";
         m_ddRearmCountToday = 0;
      }

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_dayStartBalance <= 0.0)
         m_dayStartBalance = balance;

      double dailyDDPct = 0.0;
      if(m_dayStartBalance > 0.0 && equity < m_dayStartBalance)
         dailyDDPct = ((m_dayStartBalance - equity) / m_dayStartBalance) * 100.0;

      m_status.dayStartBalance      = m_dayStartBalance;
      m_status.currentDailyDDPct    = dailyDDPct;
      m_status.currentFloatingPL    = symbolFloatingPL;
      m_status.currentOpenPositions = openPosCount;

      m_status.emergencyActive = (m_emergencyInput || m_emergencyManual);

      if(m_maxDailyDDPct > 0.0 && dailyDDPct >= m_maxDailyDDPct)
         m_dailyDDLatched = true;
      m_status.maxDailyDDHit = m_dailyDDLatched;

      m_status.maxFloatingLossHit = false;
      if(m_maxFloatingLoss > 0.0 && symbolFloatingPL < 0.0)
      {
         double absLoss = MathAbs(symbolFloatingPL);
         if(m_floatingLossMode == GT_LOSS_CURRENCY)
         {
            if(absLoss >= m_maxFloatingLoss)
               m_status.maxFloatingLossHit = true;
         }
         else
         {
            double lossPct = (balance > 0.0) ? (absLoss / balance) * 100.0 : 0.0;
            if(lossPct >= m_maxFloatingLoss)
               m_status.maxFloatingLossHit = true;
         }
      }

      m_status.maxLevelReached = (currentRecoveryLevel >= m_maxLevel);
      m_status.maxPositionsHit = (openPosCount >= m_maxOpenPositions);

      m_status.tradingHalted = false;
      m_status.haltReason    = "SAFE";

      if(m_status.emergencyActive)
      {
         m_status.tradingHalted = true;
         m_status.haltReason    = "EMERGENCY STOP AKTIF";
         NotifyBreach(m_status.haltReason);
      }
      else if(m_status.maxDailyDDHit)
      {
         m_status.tradingHalted = true;
         m_status.haltReason    = StringFormat("MAX DAILY DD (%.2f%% >= %.2f%%)%s",
                                               dailyDDPct, m_maxDailyDDPct,
                                               CanRearmAfterDD() ? " | tunggu sinyal baru" : "");
         NotifyBreach(m_status.haltReason);
      }
      else if(m_status.maxFloatingLossHit)
      {
         m_status.tradingHalted = true;
         m_status.haltReason    = StringFormat("MAX FLOATING LOSS TERCAPAI (%.2f)", symbolFloatingPL);
         NotifyBreach(m_status.haltReason);
      }
      else if(m_status.maxLevelReached && (openPosCount > 0 || pendingRecovery))
      {
         m_status.tradingHalted = true;
         m_status.haltReason    = StringFormat("MAX MARTINGALE LEVEL TERCAPAI (Level %d/%d)",
                                               currentRecoveryLevel, m_maxLevel);
         NotifyBreach(m_status.haltReason);
      }
      else if(m_status.maxPositionsHit)
      {
         m_status.tradingHalted = true;
         m_status.haltReason    = StringFormat("MAX OPEN POSITIONS TERCAPAI (%d/%d)",
                                               openPosCount, m_maxOpenPositions);
         NotifyBreach(m_status.haltReason);
      }
      else
      {
         m_lastAlertedReason = "";
      }
   }

   bool CanOpenNewEntry() const
   {
      if(m_status.emergencyActive)    return false;
      if(m_status.maxDailyDDHit)      return false;
      if(m_status.maxFloatingLossHit) return false;
      if(m_status.maxPositionsHit)    return false;
      return true;
   }

   bool CanExecuteRecovery(const int nextLevel, const bool isFlipCloseFirst) const
   {
      if(m_status.emergencyActive)    return false;
      if(m_status.maxDailyDDHit)      return false;
      if(m_status.maxFloatingLossHit) return false;
      if(nextLevel > m_maxLevel)      return false;
      if(!isFlipCloseFirst && m_status.maxPositionsHit)
         return false;
      return true;
   }
};

//+------------------------------------------------------------------+
//| CRecoveryEngine                                                  |
//+------------------------------------------------------------------+
class CRecoveryEngine
{
private:
   CTrade                  m_trade;
   string                  m_symbol;
   ENUM_TIMEFRAMES         m_tf;
   long                    m_magic;
   int                     m_slippagePts;

   double                  m_initialLot;
   double                  m_multiplier;
   double                  m_gridStepPips;
   ENUM_GT_SLTP_MODE       m_sltpMode;
   ENUM_GT_RR_MODE         m_rrMode;
   double                  m_customRR;
   double                  m_fixedSLPips;
   double                  m_fixedTPPips;
   ENUM_GT_CLASSIC_TP_MODE m_classicTPMode;
   bool                    m_onlyEntryInKillZone;
   double                  m_maxSpreadPips;
   bool                    m_rejectInvalidIndTP;
   bool                    m_strictRRValidation;
   bool                    m_enforceExactRR;
   bool                    m_enablePostSLRecovery;
   ENUM_GT_FLIP_EXEC_MODE  m_flipExecMode;
   bool                    m_flipMustEndInTP;
   bool                    m_flipAutoCoverLossTP;
   bool                    m_alertsEnabled;

   //--- v1.32
   bool                    m_abandonStuckCycle;
   datetime                m_ddHaltBar;

   //--- v1.33
   bool                    m_flipInheritSL;     // Flip memakai jarak SL entry awal (RR presisi & matematika martingale konsisten)
   bool                    m_commentReason;     // Tulis alasan entry di komentar order MT5
   double                  m_lastSLDistPx;      // Jarak SL final order terakhir (harga)
   double                  m_lastTPDistPx;      // Jarak TP final order terakhir (harga)

   SRecoveryState          m_state;
   datetime                m_lastEntrySignalBar;
   string                  m_lastRuntimeWarning;
   string                  m_lastActionLog;
   bool                    m_isFlipClosing;

   ENUM_ORDER_TYPE_FILLING DetectFillingMode(const string sym) const
   {
      long filling = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;
      if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
   }

   void LogAction(const string msg)
   {
      m_lastActionLog = msg;
      Print("[GT Recovery Engine] ", msg);
   }

   //--- [v1.33] Susun komentar order: "<TAG>|<alasan>" (maks 31 karakter, batas MT5).
   //    Awalan tag (GT_ENTRY_L0 / GT_FLIP_Ln / GT_CLASSIC_Ln) TIDAK diubah karena
   //    SyncFromOpenPositions() membaca level & mode dari awalan ini.
   string MakeComment(const string tag, const string reason) const
   {
      if(!m_commentReason || reason == "")
         return tag;

      string r = reason;
      StringReplace(r, " ", "");
      string c = tag + "|" + r;
      if(StringLen(c) > 31)
         c = StringSubstr(c, 0, 31);
      return c;
   }

   //--- [v1.33] "BUY(8): CRT_Bull+xSSL" -> "CRT_Bull+xSSL"
   string CompactSignalReason(const string fullReason) const
   {
      int p = StringFind(fullReason, ": ");
      if(p >= 0)
         return StringSubstr(fullReason, p + 2);
      return fullReason;
   }

   //--- Menghitung jarak SL & TP final (dalam harga) untuk satu order.
   bool ResolveOrderSLTP(const ENUM_GT_DIR dir,
                         const double entryPrice,
                         const double orderLot,
                         const bool   isFlipRecovery,
                         const CPipConverter &pipConv,
                         const SIndicatorData &ind,
                         double &outSL,
                         double &outTP,
                         double &outSLDistPx,
                         double &outTPDistPx)
   {
      outSL       = 0.0;
      outTP       = 0.0;
      outSLDistPx = 0.0;
      outTPDistPx = 0.0;

      double targetRR   = GT_ResolveRR(m_rrMode, m_customRR);
      double minStopPx  = pipConv.PipsToPrice(pipConv.GetMinStopPips() + 0.5);
      double gridStepPx = pipConv.PipsToPrice(m_gridStepPips);
      bool   isBuy      = (dir == GT_DIR_BUY);

      double slDistPx   = 0.0;
      double tpDistPx   = 0.0;

      if(m_sltpMode == GT_SLTP_INDICATOR)
      {
         // Entry awal: SL/TP dari indikator. Flip: indikator TIDAK dipakai (rawSL/rawTP = 0)
         double rawSL = (!isFlipRecovery) ? (isBuy ? ind.buySL : ind.sellSL) : 0.0;
         double rawTP = (!isFlipRecovery) ? (isBuy ? ind.buyTP : ind.sellTP) : 0.0;

         bool slValid = isBuy ? (rawSL > 0.0 && rawSL < entryPrice) : (rawSL > entryPrice);
         bool tpValid = isBuy ? (rawTP > entryPrice) : (rawTP > 0.0 && rawTP < entryPrice);

         if(slValid)
            slDistPx = MathAbs(entryPrice - rawSL);
         else if(m_fixedSLPips > 0.0)
            slDistPx = pipConv.PipsToPrice(m_fixedSLPips);

         if(m_enforceExactRR && slDistPx > 0.0 && targetRR > 0.0)
         {
            if(slDistPx < minStopPx)
               slDistPx = minStopPx;
            double minSLForGridPx = gridStepPx / targetRR;
            if(slDistPx < minSLForGridPx)
               slDistPx = minSLForGridPx;

            slDistPx = pipConv.NormalizePrice(slDistPx);
            tpDistPx = pipConv.NormalizePrice(slDistPx * targetRR);
         }
         else
         {
            if(tpValid)
               tpDistPx = MathAbs(rawTP - entryPrice);
            else if(slDistPx > 0.0)
               tpDistPx = slDistPx * targetRR;
            else if(m_fixedTPPips > 0.0)
               tpDistPx = pipConv.PipsToPrice(m_fixedTPPips);
         }
      }
      else if(m_sltpMode == GT_SLTP_FIXED_PIP)
      {
         slDistPx = pipConv.NormalizePrice(pipConv.PipsToPrice(m_fixedSLPips));
         tpDistPx = pipConv.NormalizePrice(pipConv.PipsToPrice(m_fixedTPPips));
      }
      else
      {
         double slPips = m_fixedSLPips;
         if(slPips <= 0.0 && !isFlipRecovery && ind.valid)
         {
            double rawSL = isBuy ? ind.buySL : ind.sellSL;
            bool slValid = isBuy ? (rawSL > 0.0 && rawSL < entryPrice) : (rawSL > entryPrice);
            if(slValid)
               slPips = pipConv.PriceToPips(MathAbs(entryPrice - rawSL));
         }
         slDistPx = pipConv.PipsToPrice(slPips);
         if(slDistPx < minStopPx)
            slDistPx = minStopPx;
         if(targetRR > 0.0 && slDistPx * targetRR < gridStepPx)
            slDistPx = gridStepPx / targetRR;

         slDistPx = pipConv.NormalizePrice(slDistPx);
         tpDistPx = pipConv.NormalizePrice(slDistPx * targetRR);
      }

      //--- [v1.33] FLIP MEWARISI JARAK SL ENTRY AWAL.
      //    Sebelumnya Flip memakai SL fallback (InpFixedSLPips) yang BERBEDA dari SL struktural L0,
      //    sehingga rasio kerugian L0 vs target TP Flip tidak konsisten dengan RR/multiplier.
      //    Sekarang: SL Flip = SL siklus (dijaga >= StopsLevel & >= GridStep/RR), TP = SL x RR persis.
      //    Mode Fixed Pip tidak diubah (SL/TP sudah tetap sama di semua level).
      if(isFlipRecovery && m_flipInheritSL &&
         m_sltpMode != GT_SLTP_FIXED_PIP && m_state.cycleSLDistPx > 0.0 && targetRR > 0.0)
      {
         double inhSL = m_state.cycleSLDistPx;
         if(inhSL < minStopPx)
            inhSL = minStopPx;
         double minSLForGridPx2 = gridStepPx / targetRR;
         if(inhSL < minSLForGridPx2)
            inhSL = minSLForGridPx2;

         slDistPx = pipConv.NormalizePrice(inhSL);
         tpDistPx = pipConv.NormalizePrice(slDistPx * targetRR);
      }

      if(isFlipRecovery && m_flipAutoCoverLossTP && m_state.realizedCyclePL < 0.0 && orderLot > 0.0)
      {
         double pipValOrder = pipConv.GetPipValuePerLot() * orderLot;
         if(pipValOrder > 0.0)
         {
            double needCoverPips = (MathAbs(m_state.realizedCyclePL) / pipValOrder) + MathMax(3.0, m_gridStepPips * 0.25);
            double curTPPips     = pipConv.PriceToPips(tpDistPx);
            if(needCoverPips > curTPPips)
               tpDistPx = pipConv.NormalizePrice(pipConv.PipsToPrice(needCoverPips));
         }
      }

      double slPipsActual = pipConv.PriceToPips(slDistPx);
      double tpPipsActual = pipConv.PriceToPips(tpDistPx);

      SValidationResult vr = CConfigValidator::ValidateRuntimeSLTP(slPipsActual,
                                                                   tpPipsActual,
                                                                   m_gridStepPips,
                                                                   targetRR,
                                                                   m_strictRRValidation && !isFlipRecovery);
      if(vr.hasWarning)
      {
         m_lastRuntimeWarning = vr.warningMessage;
         Print("[GT Recovery Engine] ", vr.warningMessage);
      }
      if(!vr.isValid)
      {
         m_lastRuntimeWarning = vr.errorMessage;
         Print("[GT Recovery Engine][REJECT] ", vr.errorMessage);
         if(m_alertsEnabled && !MQLInfoInteger(MQL_OPTIMIZATION))
            Alert("[GT Recovery Engine] ", vr.errorMessage);

         //--- [v1.33] Order FLIP tidak boleh ditolak (siklus tanpa posisi akan macet tanpa hedge).
         //    Entry awal/klasik tetap boleh ditolak jika InpRejectInvalidIndTP aktif.
         if(m_rejectInvalidIndTP && !isFlipRecovery)
            return false;

         if(tpPipsActual < m_gridStepPips)
         {
            tpDistPx = pipConv.NormalizePrice(gridStepPx);
            if(m_enforceExactRR && targetRR > 0.0)
               slDistPx = pipConv.NormalizePrice(tpDistPx / targetRR);
         }
      }

      if(slDistPx > 0.0 && slDistPx < minStopPx)
      {
         slDistPx = pipConv.NormalizePrice(minStopPx);
         if(m_enforceExactRR && m_sltpMode != GT_SLTP_FIXED_PIP && targetRR > 0.0)
            tpDistPx = pipConv.NormalizePrice(slDistPx * targetRR);
      }
      if(tpDistPx > 0.0 && tpDistPx < minStopPx)
         tpDistPx = pipConv.NormalizePrice(minStopPx);

      outSLDistPx = slDistPx;
      outTPDistPx = tpDistPx;

      if(slDistPx > 0.0)
         outSL = pipConv.NormalizePrice(isBuy ? (entryPrice - slDistPx) : (entryPrice + slDistPx));
      if(tpDistPx > 0.0)
         outTP = pipConv.NormalizePrice(isBuy ? (entryPrice + tpDistPx) : (entryPrice - tpDistPx));

      return true;
   }

   bool SendMarketOrder(const ENUM_GT_DIR dir,
                        const double rawLot,
                        const bool   isFlipRecovery,
                        const CPipConverter &pipConv,
                        const SIndicatorData &ind,
                        const string comment,
                        double &executedPrice,
                        double &executedLot)
   {
      executedPrice = 0.0;
      executedLot   = pipConv.NormalizeLot(rawLot);

      if(executedLot <= 0.0)
         return false;

      bool   isBuy      = (dir == GT_DIR_BUY);
      double entryPrice = isBuy
                          ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(entryPrice <= 0.0)
         return false;

      double sl = 0.0, tp = 0.0, slDistPx = 0.0, tpDistPx = 0.0;
      if(!ResolveOrderSLTP(dir, entryPrice, executedLot, isFlipRecovery, pipConv, ind, sl, tp, slDistPx, tpDistPx))
         return false;

      bool ok = false;
      if(isBuy)
         ok = m_trade.Buy(executedLot, m_symbol, entryPrice, sl, tp, comment);
      else
         ok = m_trade.Sell(executedLot, m_symbol, entryPrice, sl, tp, comment);

      if(!ok)
      {
         PrintFormat("[GT Recovery Engine][ORDER FAIL] %s Lot=%.2f RetCode=%u (%s)",
                     GT_DirToString(dir), executedLot,
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
         return false;
      }

      //--- Post-Fill Exact SL/TP Re-Anchor (RR tetap presisi walau ada slippage)
      executedPrice = (m_trade.ResultPrice() > 0.0) ? m_trade.ResultPrice() : entryPrice;
      double finalSL = sl;
      double finalTP = tp;

      if(slDistPx > 0.0 && tpDistPx > 0.0)
      {
         //--- [v1.33] Cari tiket posisi lewat DEAL ID hasil order (akurat 100%).
         //    Versi lama memilih "posisi terbaru berdasarkan detik" yang bisa salah tiket
         //    bila ada >1 posisi searah dalam detik yang sama.
         ulong posTicket = 0;
         ulong dealTk    = m_trade.ResultDeal();
         if(dealTk > 0 && HistoryDealSelect(dealTk))
         {
            ulong posId = (ulong)HistoryDealGetInteger(dealTk, DEAL_POSITION_ID);
            if(posId > 0 && PositionSelectByTicket(posId))
               posTicket = posId;
         }

         //--- Fallback: pindai posisi terbaru searah (perilaku lama)
         if(posTicket == 0)
         {
            datetime newestOT = 0;
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               ulong t = PositionGetTicket(i);
               if(t == 0) continue;
               if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
               if(PositionGetInteger(POSITION_MAGIC) != m_magic)  continue;
               long pType = PositionGetInteger(POSITION_TYPE);
               if((isBuy && pType != POSITION_TYPE_BUY) || (!isBuy && pType != POSITION_TYPE_SELL))
                  continue;
               datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
               if(ot >= newestOT)
               {
                  newestOT  = ot;
                  posTicket = t;
               }
            }
         }

         if(posTicket > 0 && PositionSelectByTicket(posTicket))
         {
            double fillPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double curSL     = PositionGetDouble(POSITION_SL);
            double curTP     = PositionGetDouble(POSITION_TP);
            if(fillPrice > 0.0)
            {
               executedPrice  = fillPrice;
               double exactSL = pipConv.NormalizePrice(isBuy ? (fillPrice - slDistPx) : (fillPrice + slDistPx));
               double exactTP = pipConv.NormalizePrice(isBuy ? (fillPrice + tpDistPx) : (fillPrice - tpDistPx));
               double tickSz  = MathMax(pipConv.PointSize(), SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE));

               if(MathAbs(exactSL - curSL) >= tickSz || MathAbs(exactTP - curTP) >= tickSz)
               {
                  //--- [v1.33] Coba hingga 3x dan LOG bila gagal (sebelumnya gagal diam-diam,
                  //    sehingga SL/TP tetap meleset dari RR tanpa ada peringatan).
                  bool modOK = false;
                  for(int attempt = 0; attempt < 3 && !modOK; attempt++)
                  {
                     if(attempt > 0)
                        Sleep(150);
                     modOK = m_trade.PositionModify(posTicket, exactSL, exactTP);
                  }

                  if(modOK)
                  {
                     finalSL = exactSL;
                     finalTP = exactTP;
                  }
                  else
                  {
                     finalSL = curSL;
                     finalTP = curTP;
                     PrintFormat("[GT Recovery Engine][WARN] Re-anchor SL/TP GAGAL (Ticket=%I64u RetCode=%u %s). SL/TP tetap di nilai order awal (bisa meleset dari RR akibat slippage).",
                                 posTicket, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
                  }
               }
            }
         }
      }

      double actualSLPips = (finalSL > 0.0) ? pipConv.PriceToPips(MathAbs(executedPrice - finalSL)) : 0.0;
      double actualTPPips = (finalTP > 0.0) ? pipConv.PriceToPips(MathAbs(finalTP - executedPrice)) : 0.0;
      double actualRR     = (actualSLPips > 0.0) ? (actualTPPips / actualSLPips) : 0.0;

      //--- [v1.33] Simpan jarak SL/TP aktual (harga) agar bisa diwariskan ke Flip
      m_lastSLDistPx = (finalSL > 0.0) ? MathAbs(executedPrice - finalSL) : slDistPx;
      m_lastTPDistPx = (finalTP > 0.0) ? MathAbs(finalTP - executedPrice) : tpDistPx;

      LogAction(StringFormat("OPEN %s | Lot=%.2f | Open=%s | SL=%s (%.1f pip) | TP=%s (%.1f pip) | RR=1:%.2f | %s",
                             GT_DirToString(dir),
                             executedLot,
                             DoubleToString(executedPrice, pipConv.Digits()),
                             DoubleToString(finalSL, pipConv.Digits()), actualSLPips,
                             DoubleToString(finalTP, pipConv.Digits()), actualTPPips,
                             actualRR,
                             comment));
      return true;
   }

   void AlignClassicBasketTP(const ENUM_GT_DIR dir, const CPipConverter &pipConv)
   {
      if(m_classicTPMode != GT_CLASSIC_TP_BASKET)
         return;

      double totalVol = 0.0;
      double weightedPx = 0.0;
      int    count = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)  continue;

         long pType = PositionGetInteger(POSITION_TYPE);
         if((dir == GT_DIR_BUY  && pType != POSITION_TYPE_BUY) ||
            (dir == GT_DIR_SELL && pType != POSITION_TYPE_SELL))
            continue;

         double vol = PositionGetDouble(POSITION_VOLUME);
         double op  = PositionGetDouble(POSITION_PRICE_OPEN);
         totalVol   += vol;
         weightedPx += vol * op;
         count++;
      }

      if(count < 2 || totalVol <= 0.0)
         return;

      double avgPrice = weightedPx / totalVol;

      double targetRR  = GT_ResolveRR(m_rrMode, m_customRR);
      double baseTPPips = (m_sltpMode == GT_SLTP_RISK_REWARD) ? (m_fixedSLPips * targetRR) : m_fixedTPPips;
      if(baseTPPips < m_gridStepPips)
         baseTPPips = m_gridStepPips;

      double extraLossPips = 0.0;
      if(m_state.realizedCyclePL < 0.0)
      {
         double pipValTotal = pipConv.GetPipValuePerLot() * totalVol;
         if(pipValTotal > 0.0)
            extraLossPips = MathAbs(m_state.realizedCyclePL) / pipValTotal;
      }

      double totalTPPips = baseTPPips + extraLossPips;
      double tpPxDist    = pipConv.PipsToPrice(totalTPPips);
      double newTP       = pipConv.NormalizePrice((dir == GT_DIR_BUY) ? (avgPrice + tpPxDist) : (avgPrice - tpPxDist));

      double minStopPx = pipConv.PipsToPrice(pipConv.GetMinStopPips() + 0.5);
      double curBid    = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double curAsk    = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      if(dir == GT_DIR_BUY && newTP <= curAsk + minStopPx)
         newTP = pipConv.NormalizePrice(curAsk + MathMax(minStopPx, pipConv.PipsToPrice(m_gridStepPips)));
      if(dir == GT_DIR_SELL && newTP >= curBid - minStopPx)
         newTP = pipConv.NormalizePrice(curBid - MathMax(minStopPx, pipConv.PipsToPrice(m_gridStepPips)));

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)  continue;

         long pType = PositionGetInteger(POSITION_TYPE);
         if((dir == GT_DIR_BUY  && pType != POSITION_TYPE_BUY) ||
            (dir == GT_DIR_SELL && pType != POSITION_TYPE_SELL))
            continue;

         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if(MathAbs(curTP - newTP) >= pipConv.PointSize())
            m_trade.PositionModify(ticket, curSL, newTP);
      }
   }

public:
   CRecoveryEngine()
   {
      m_symbol               = _Symbol;
      m_tf                   = PERIOD_CURRENT;
      m_magic                = 20261121;
      m_slippagePts          = 20;
      m_initialLot           = 0.01;
      m_multiplier           = 1.5;
      m_gridStepPips         = 20.0;
      m_sltpMode             = GT_SLTP_INDICATOR;
      m_rrMode               = GT_RR_1_2;
      m_customRR             = 2.0;
      m_fixedSLPips          = 20.0;
      m_fixedTPPips          = 40.0;
      m_classicTPMode        = GT_CLASSIC_TP_BASKET;
      m_onlyEntryInKillZone  = false;
      m_maxSpreadPips        = 0.0;
      m_rejectInvalidIndTP   = true;
      m_strictRRValidation   = false;
      m_enforceExactRR       = true;
      m_enablePostSLRecovery = true;
      m_flipExecMode         = GT_FLIP_DIRECT_ON_SL;
      m_flipMustEndInTP      = true;
      m_flipAutoCoverLossTP  = false;
      m_alertsEnabled        = true;
      m_abandonStuckCycle    = true;
      m_ddHaltBar            = 0;
      m_flipInheritSL        = true;
      m_commentReason        = true;
      m_lastSLDistPx         = 0.0;
      m_lastTPDistPx         = 0.0;
      m_lastEntrySignalBar   = 0;
      m_lastRuntimeWarning   = "";
      m_lastActionLog        = "Engine Initialized";
      m_isFlipClosing        = false;
      m_state.Reset();
   }

   void Init(const string symbol,
             const ENUM_TIMEFRAMES tf,
             const long magic,
             const int slippagePts,
             const double initialLot,
             const double multiplier,
             const double gridStepPips,
             const ENUM_GT_SLTP_MODE sltpMode,
             const ENUM_GT_RR_MODE rrMode,
             const double customRR,
             const double fixedSLPips,
             const double fixedTPPips,
             const ENUM_GT_CLASSIC_TP_MODE classicTPMode,
             const bool onlyEntryInKillZone,
             const double maxSpreadPips,
             const bool rejectInvalidIndTP,
             const bool strictRRValidation,
             const bool enforceExactRR,
             const bool enablePostSLRecovery,
             const ENUM_GT_FLIP_EXEC_MODE flipExecMode,
             const bool flipMustEndInTP,
             const bool flipAutoCoverLossTP,
             const bool alertsEnabled)
   {
      m_symbol               = symbol;
      m_tf                   = tf;
      m_magic                = magic;
      m_slippagePts          = MathMax(0, slippagePts);
      m_initialLot           = initialLot;
      m_multiplier           = multiplier;
      m_gridStepPips         = gridStepPips;
      m_sltpMode             = sltpMode;
      m_rrMode               = rrMode;
      m_customRR             = customRR;
      m_fixedSLPips          = fixedSLPips;
      m_fixedTPPips          = fixedTPPips;
      m_classicTPMode        = classicTPMode;
      m_onlyEntryInKillZone  = onlyEntryInKillZone;
      m_maxSpreadPips        = MathMax(0.0, maxSpreadPips);
      m_rejectInvalidIndTP   = rejectInvalidIndTP;
      m_strictRRValidation   = strictRRValidation;
      m_enforceExactRR       = enforceExactRR;
      m_enablePostSLRecovery = enablePostSLRecovery;
      m_flipExecMode         = flipExecMode;
      m_flipMustEndInTP      = flipMustEndInTP;
      m_flipAutoCoverLossTP  = flipAutoCoverLossTP;
      m_alertsEnabled        = alertsEnabled;
      m_ddHaltBar            = 0;

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippagePts);
      m_trade.SetTypeFilling(DetectFillingMode(m_symbol));
      m_trade.SetAsyncMode(false);

      m_state.Reset();
      SyncFromOpenPositions();
   }

   //--- v1.32
   void SetAbandonStuckCycle(const bool v) { m_abandonStuckCycle = v; }

   //--- v1.33
   void SetFlipInheritSL(const bool v)      { m_flipInheritSL = v; }
   void SetCommentEntryReason(const bool v) { m_commentReason = v; }

   SRecoveryState GetState() const          { return m_state; }
   string         GetRuntimeWarning() const { return m_lastRuntimeWarning; }
   string         GetLastActionLog() const  { return m_lastActionLog; }
   void           ResetCycle()              { m_state.Reset(); }

   void QueryPositions(int &count,
                       double &floatingPL,
                       double &totalLots,
                       ENUM_GT_DIR &dominantDir,
                       double &latestEntryPrice,
                       double &latestLot) const
   {
      count            = 0;
      floatingPL       = 0.0;
      totalLots        = 0.0;
      dominantDir      = GT_DIR_NONE;
      latestEntryPrice = 0.0;
      latestLot        = 0.0;

      datetime newestTime = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)  continue;

         count++;
         double vol  = PositionGetDouble(POSITION_VOLUME);
         double prof = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
         long pType  = PositionGetInteger(POSITION_TYPE);

         totalLots  += vol;
         floatingPL += prof;

         if(ot >= newestTime)
         {
            newestTime       = ot;
            latestEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            latestLot        = vol;
            dominantDir      = (pType == POSITION_TYPE_BUY) ? GT_DIR_BUY : GT_DIR_SELL;
         }
      }
   }

   void SyncFromOpenPositions()
   {
      int count = 0;
      double flt = 0.0, lots = 0.0, lastPx = 0.0, lastLot = 0.0;
      ENUM_GT_DIR dir = GT_DIR_NONE;

      QueryPositions(count, flt, lots, dir, lastPx, lastLot);
      if(count > 0)
      {
         int parsedMaxLv = count - 1;
         ENUM_GT_RECOVERY_MODE parsedMode = m_state.lastMode;
         datetime newestTime = 0;

         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_magic)  continue;

            string cmt  = PositionGetString(POSITION_COMMENT);
            datetime ot = (datetime)PositionGetInteger(POSITION_TIME);

            // Level dibaca dari "_L<angka>" di awal komentar (alasan setelah '|' diabaikan)
            int posL = StringFind(cmt, "_L");
            if(posL >= 0)
            {
               int lv = (int)StringToInteger(StringSubstr(cmt, posL + 2));
               if(lv > parsedMaxLv)
                  parsedMaxLv = lv;
            }
            if(ot >= newestTime)
            {
               newestTime = ot;
               if(StringFind(cmt, "GT_FLIP_") >= 0)         parsedMode = GT_REC_FLIP;
               else if(StringFind(cmt, "GT_CLASSIC_") >= 0) parsedMode = GT_REC_CLASSIC;
            }

            //--- [v1.33] Pulihkan jarak SL siklus dari posisi terbuka (setelah restart EA / ganti chart)
            if(m_state.cycleSLDistPx <= 0.0)
            {
               double pSL = PositionGetDouble(POSITION_SL);
               double pOP = PositionGetDouble(POSITION_PRICE_OPEN);
               if(pSL > 0.0 && pOP > 0.0)
                  m_state.cycleSLDistPx = MathAbs(pOP - pSL);
            }
         }

         m_state.cycleActive     = true;
         m_state.flipCycleLocked = (parsedMode == GT_REC_FLIP) ? true : m_state.flipCycleLocked;
         m_state.currentDir      = dir;
         m_state.currentLevel    = MathMax(m_state.currentLevel, parsedMaxLv);
         m_state.lastMode        = parsedMode;
         m_state.lastEntryPrice  = lastPx;
         m_state.lastLot         = lastLot;
      }
   }

   bool ClosePositions(const ENUM_GT_DIR filterDir = GT_DIR_NONE)
   {
      bool allClosed = true;

      for(int pass = 0; pass < 3; pass++)
      {
         int remaining = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_magic)  continue;

            long pType = PositionGetInteger(POSITION_TYPE);
            if(filterDir == GT_DIR_BUY  && pType != POSITION_TYPE_BUY)  continue;
            if(filterDir == GT_DIR_SELL && pType != POSITION_TYPE_SELL) continue;

            remaining++;
            if(!m_trade.PositionClose(ticket, m_slippagePts))
            {
               PrintFormat("[GT Recovery Engine][CLOSE FAIL] Ticket=%I64u RetCode=%u (%s)",
                           ticket, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
               allClosed = false;
            }
         }
         if(remaining == 0)
            return true;
      }

      return allClosed;
   }

   void OnDealTransaction(const MqlTradeTransaction &trans)
   {
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
         return;

      ulong dealTicket = trans.deal;
      if(dealTicket == 0 || !HistoryDealSelect(dealTicket))
         return;

      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != m_symbol) return;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != m_magic)  return;

      long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT)
         return;

      double dealPL = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                    + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                    + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      long   dealReason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      long   dealType   = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      double dealPrice  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double dealVol    = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

      // Deal penutup BUY berjenis SELL (dan sebaliknya) -> arah posisi yang baru ditutup
      ENUM_GT_DIR closedPosDir = (dealType == DEAL_TYPE_SELL) ? GT_DIR_BUY : GT_DIR_SELL;

      m_state.realizedCyclePL += dealPL;
      if(dealVol > m_state.lastLot)
         m_state.lastLot = dealVol;

      if(m_isFlipClosing)
         return;

      int openCount = 0;
      double flt = 0.0, lots = 0.0, lastPx = 0.0, lastLot = 0.0;
      ENUM_GT_DIR dir = GT_DIR_NONE;
      QueryPositions(openCount, flt, lots, dir, lastPx, lastLot);

      if(openCount == 0)
      {
         bool directOnSL = (m_flipExecMode == GT_FLIP_DIRECT_ON_SL);
         bool flipLocked = (m_flipMustEndInTP && m_state.flipCycleLocked);

         //--- 1. TP -> siklus tuntas, reset ke Level 0
         if(dealReason == DEAL_REASON_TP)
         {
            LogAction(StringFormat("%s TUNTAS TP! (Deal=%+.2f | Net Cycle=%+.2f) -> Reset ke Level 0, diizinkan mencari sinyal baru.",
                                   (m_state.flipCycleLocked || directOnSL) ? "FLIP MARTINGALE" : "CYCLE",
                                   dealPL, m_state.realizedCyclePL));
            m_state.Reset();
            return;
         }

         //--- 2. Direct Flip saat SL
         //    ALASAN ENTRY FLIP: posisi sebelumnya kena SL -> langsung balik arah dengan lot x multiplier
         if(directOnSL && (dealReason == DEAL_REASON_SL || dealPL < 0.0 || m_state.flipCycleLocked))
         {
            ENUM_GT_DIR nextFlipDir = (closedPosDir == GT_DIR_BUY) ? GT_DIR_SELL : GT_DIR_BUY;
            m_state.cycleActive         = true;
            m_state.flipCycleLocked     = true;
            m_state.pendingPostSLReEval = true;
            m_state.lastLostDir         = closedPosDir;
            m_state.lastLostPrice       = dealPrice;
            LogAction(StringFormat("DIRECT FLIP: %s kena SL (%+.2f | Cycle=%+.2f) -> Langsung balik arah ke %s (lot Martingale) menuju TP!",
                                   GT_DirToString(closedPosDir), dealPL, m_state.realizedCyclePL,
                                   GT_DirToString(nextFlipDir)));
            return;
         }

         //--- 3. Siklus Flip terkunci (Hybrid / Prob-Gated)
         if(flipLocked)
         {
            m_state.cycleActive         = true;
            m_state.flipCycleLocked     = true;
            m_state.pendingPostSLReEval = true;
            m_state.lastLostDir         = closedPosDir;
            m_state.lastLostPrice       = dealPrice;
            LogAction(StringFormat("FLIP BELUM TP (%s Closed %+.2f | Cycle=%+.2f) -> Siklus Flip TERKUNCI, lanjut recovery menuju TP.",
                                   GT_DirToString(closedPosDir), dealPL, m_state.realizedCyclePL));
            return;
         }

         //--- 4. Siklus normal / Martingale Klasik
         if(m_state.realizedCyclePL >= 0.0)
         {
            LogAction(StringFormat("CYCLE SELESAI PROFIT (Net=%+.2f) -> Reset ke Level 0 (Siap cari sinyal baru).",
                                   m_state.realizedCyclePL));
            m_state.Reset();
         }
         else if(m_enablePostSLRecovery && dealPL < 0.0 && m_state.cycleActive)
         {
            m_state.pendingPostSLReEval = true;
            m_state.lastLostDir         = closedPosDir;
            m_state.lastLostPrice       = dealPrice;
            LogAction(StringFormat("POSISI %s CLOSED LOSS (%+.2f | Cycle=%+.2f) -> Memicu Evaluasi Ulang Probabilitas.",
                                   GT_DirToString(closedPosDir), dealPL, m_state.realizedCyclePL));
         }
         else
         {
            m_state.Reset();
         }
      }
   }

   //+----------------------------------------------------------------+
   //| Main Tick Processing                                           |
   //+----------------------------------------------------------------+
   void ProcessTick(const CPipConverter &pipConv,
                    const CIndicatorBridge &indBridge,
                    const SIndicatorData &ind,
                    const SMarketContext &ctx,
                    CProbabilityEngine &probEngine,
                    CSafetyManager &safety)
   {
      int openCount = 0;
      double fltPL = 0.0, totalLots = 0.0, lastPx = 0.0, lastLot = 0.0;
      ENUM_GT_DIR openDir = GT_DIR_NONE;
      QueryPositions(openCount, fltPL, totalLots, openDir, lastPx, lastLot);

      safety.Update(m_state.currentLevel, openCount, fltPL, m_state.pendingPostSLReEval);

      //--- Emergency close-all
      if(safety.GetStatus().emergencyActive && safety.ShouldCloseAllOnEmergency() && openCount > 0)
      {
         LogAction("EMERGENCY STOP: Menutup seluruh posisi terbuka.");
         ClosePositions(GT_DIR_NONE);
         m_state.Reset();
         return;
      }

      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
         return;

      if(m_maxSpreadPips > 0.0 && pipConv.GetSpreadPips() > m_maxSpreadPips)
         return;

      datetime curBarTime = iTime(m_symbol, m_tf, 0);

      //================================================================
      // v1.32 PRE-BRANCH: ANTI-DEADLOCK + DD RESUME ON NEXT SIGNAL
      //================================================================
      {
         SSafetyStatus st = safety.GetStatus();

         //--- Catat bar saat DD pertama kali terdeteksi (sinyal "berikutnya" harus bar yang lebih baru)
         if(st.maxDailyDDHit)
         {
            if(m_ddHaltBar == 0)
               m_ddHaltBar = (ind.valid && ind.barTime > 0) ? ind.barTime : curBarTime;
         }
         else
            m_ddHaltBar = 0;

         if(openCount == 0)
         {
            bool cycleOpen   = (m_state.cycleActive || m_state.flipCycleLocked || m_state.pendingPostSLReEval);
            bool ddHalt      = st.maxDailyDDHit;
            bool lvExhausted = m_state.pendingPostSLReEval &&
                               ((m_state.currentLevel + 1) > safety.MaxLevel());

            //--- Batalkan siklus yang macet (tanpa posisi) agar EA tidak deadlock
            if(m_abandonStuckCycle && cycleOpen && (ddHalt || lvExhausted))
            {
               LogAction(StringFormat("SIKLUS DIBATALKAN (%s) | Net Cycle=%+.2f -> Reset ke Level 0, menunggu sinyal baru.",
                                      ddHalt ? "Daily DD tercapai" : "Max Martingale Level habis",
                                      m_state.realizedCyclePL));
               m_state.Reset();
            }

            //--- DD RESUME: buka kunci DD begitu ada sinyal valid pada bar yang lebih baru
            if(ddHalt && safety.CanRearmAfterDD() &&
               !m_state.flipCycleLocked && !m_state.pendingPostSLReEval)
            {
               bool freshSignal = ind.valid &&
                                  ind.barTime > m_ddHaltBar &&
                                  ind.barTime != m_lastEntrySignalBar &&
                                  (indBridge.IsValidBuyEntry(ind) || indBridge.IsValidSellEntry(ind));
               if(freshSignal)
               {
                  LogAction(StringFormat("DD RESUME: sinyal baru terdeteksi (%s) -> proteksi DD di-rearm, baseline DD harian dimulai ulang.",
                                         ind.signalReason));
                  safety.RearmAfterDD();
                  safety.Update(0, 0, 0.0, false);
                  m_ddHaltBar = 0;
               }
            }
         }
      }

      //================================================================
      // BRANCH 1: POST-SL RECOVERY (tidak ada posisi, siklus menunggu entry lanjutan)
      // ALASAN ENTRY: posisi sebelumnya ditutup SL -> recovery level berikutnya
      //================================================================
      if(openCount == 0 && m_state.pendingPostSLReEval)
      {
         int nextLevel = m_state.currentLevel + 1;
         if(!safety.CanExecuteRecovery(nextLevel, true))
            return;

         bool useDirectFlipNow = (m_flipExecMode == GT_FLIP_DIRECT_ON_SL) ||
                                 (m_flipExecMode == GT_FLIP_HYBRID_LOCK && m_state.flipCycleLocked);

         double nextLot = pipConv.CalcNextRecoveryLot(m_state.lastLot, m_multiplier);
         double execPx = 0.0, execLot = 0.0;

         //--- 1A. DIRECT FLIP: tanpa evaluasi probabilitas, langsung balik arah dari posisi yang kena SL
         if(useDirectFlipNow)
         {
            ENUM_GT_DIR flipDir = (m_state.lastLostDir == GT_DIR_BUY) ? GT_DIR_SELL : GT_DIR_BUY;
            string reasonFlip = StringFormat("DirectFlip(%sSL)", GT_DirToString(m_state.lastLostDir));
            string tag = MakeComment(StringFormat("GT_FLIP_L%d", nextLevel), reasonFlip);

            if(SendMarketOrder(flipDir, nextLot, true, pipConv, ind, tag, execPx, execLot))
            {
               m_state.cycleActive         = true;
               m_state.flipCycleLocked     = true;
               m_state.currentDir          = flipDir;
               m_state.currentLevel        = nextLevel;
               m_state.lastMode            = GT_REC_FLIP;
               m_state.lastEntryPrice      = execPx;
               m_state.lastLot             = execLot;
               m_state.lastActionBarTime   = curBarTime;
               m_state.pendingPostSLReEval = false;
               m_state.lastEntryReason     = reasonFlip;
               m_state.flipCount++;
               if(m_state.cycleSLDistPx <= 0.0)
                  m_state.cycleSLDistPx = m_lastSLDistPx;

               probEngine.Evaluate(flipDir, ctx, ind);
               LogAction(StringFormat("DIRECT FLIP EXECUTED: %s SL -> Langsung %s | Lot=%.2f | Level=%d [WAJIB TP]",
                                      GT_DirToString(m_state.lastLostDir),
                                      GT_DirToString(flipDir), execLot, nextLevel));
            }
            return;
         }

         //--- 1B. Mode Probability-Gated / Hybrid awal: evaluasi skor reversal vs kontinuasi
         SProbabilityDecision dec = probEngine.Evaluate(m_state.lastLostDir, ctx, ind);
         if(!dec.allowExecution)
            return;

         bool   isFlipOrder = (dec.mode == GT_REC_FLIP || m_state.flipCycleLocked);
         // Alasan: faktor reversal aktif (untuk Flip) atau skor kontinuasi (untuk Klasik)
         string reasonProb  = (dec.mode == GT_REC_FLIP)
                              ? ("ProbFlip:" + dec.activeReversalFactors)
                              : StringFormat("ProbKlasik:Kont%d", dec.continuationScore);
         string tag = (dec.mode == GT_REC_FLIP)
                      ? MakeComment(StringFormat("GT_FLIP_L%d", nextLevel), reasonProb)
                      : MakeComment(StringFormat("GT_CLASSIC_L%d", nextLevel), reasonProb);

         if(SendMarketOrder(dec.recommendedDir, nextLot, isFlipOrder, pipConv, ind, tag, execPx, execLot))
         {
            m_state.cycleActive         = true;
            if(dec.mode == GT_REC_FLIP)
               m_state.flipCycleLocked  = true;
            m_state.currentDir          = dec.recommendedDir;
            m_state.currentLevel        = nextLevel;
            m_state.lastMode            = dec.mode;
            m_state.lastEntryPrice      = execPx;
            m_state.lastLot             = execLot;
            m_state.lastActionBarTime   = curBarTime;
            m_state.pendingPostSLReEval = false;
            m_state.lastEntryReason     = reasonProb;
            if(m_state.cycleSLDistPx <= 0.0)
               m_state.cycleSLDistPx = m_lastSLDistPx;
            if(dec.mode == GT_REC_FLIP) m_state.flipCount++;
            else                        m_state.classicCount++;

            LogAction("RECOVERY POST-SL: " + dec.summaryReason);
         }
         return;
      }

      //================================================================
      // BRANCH 2: INITIAL ENTRY ENGINE (GT_ENTRY_L0)
      // ALASAN ENTRY: sinyal ICT+SMC+CRT valid (skor & token konfluensi tercatat di signalReason)
      //================================================================
      if(openCount == 0)
      {
         // Siklus Flip belum TP -> dilarang mencari sinyal baru
         if(m_flipMustEndInTP && m_state.flipCycleLocked)
            return;

         // Safety: DD harian / floating loss / emergency / max posisi
         if(!safety.CanOpenNewEntry())
            return;

         // Opsional: hanya entry di dalam KillZone
         if(m_onlyEntryInKillZone && !ctx.inKillZone)
            return;

         // Satu sinyal hanya boleh dipakai sekali (per bar sinyal)
         if(!ind.valid || ind.barTime == m_lastEntrySignalBar)
            return;

         ENUM_GT_DIR entryDir = GT_DIR_NONE;
         if(indBridge.IsValidBuyEntry(ind))
            entryDir = GT_DIR_BUY;
         else if(indBridge.IsValidSellEntry(ind))
            entryDir = GT_DIR_SELL;

         if(entryDir == GT_DIR_NONE)
            return;

         double execPx = 0.0, execLot = 0.0;
         string reasonL0 = CompactSignalReason(ind.signalReason);   // mis. "CRT_Bull+xSSL+CHoCH+OTE"
         string tagL0    = MakeComment("GT_ENTRY_L0", reasonL0);
         if(SendMarketOrder(entryDir, m_initialLot, false, pipConv, ind, tagL0, execPx, execLot))
         {
            m_lastEntrySignalBar        = ind.barTime;
            m_state.Reset();
            m_state.cycleActive         = true;
            m_state.currentDir          = entryDir;
            m_state.currentLevel        = 0;
            m_state.lastMode            = GT_REC_NONE;
            m_state.lastEntryPrice      = execPx;
            m_state.lastLot             = execLot;
            m_state.lastActionBarTime   = curBarTime;
            m_state.lastEntryReason     = reasonL0;
            //--- [v1.33] Simpan jarak SL/TP entry awal -> diwariskan ke seluruh Flip siklus ini
            m_state.cycleSLDistPx       = m_lastSLDistPx;
            m_state.cycleTPDistPx       = m_lastTPDistPx;
            LogAction("ALASAN ENTRY L0: " + ind.signalReason);
         }
         return;
      }

      //================================================================
      // BRANCH 3: OPEN POSITIONS -> ADVERSE STEP TRIGGERS RE-EVALUATION
      // ALASAN ENTRY: harga melawan posisi >= Grid Step -> Flip (reversal kuat) atau Klasik (tren sehat)
      //================================================================
      if(!m_state.cycleActive)
         SyncFromOpenPositions();

      SProbabilityDecision liveDec = probEngine.Evaluate(openDir, ctx, ind);

      // Direct Flip / Hybrid terkunci: tidak ada averaging, recovery hanya lewat SL -> Flip
      if(m_flipExecMode == GT_FLIP_DIRECT_ON_SL ||
         (m_flipExecMode == GT_FLIP_HYBRID_LOCK && m_state.flipCycleLocked))
         return;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double adversePips = 0.0;

      if(openDir == GT_DIR_BUY)
         adversePips = pipConv.PriceToPips(m_state.lastEntryPrice - bid);
      else if(openDir == GT_DIR_SELL)
         adversePips = pipConv.PriceToPips(ask - m_state.lastEntryPrice);

      if(adversePips < m_gridStepPips)
         return;

      // Satu aksi recovery per bar
      if(curBarTime == m_state.lastActionBarTime)
         return;

      int nextLevel = m_state.currentLevel + 1;
      double nextLot = pipConv.CalcNextRecoveryLot(m_state.lastLot, m_multiplier);

      if(liveDec.mode == GT_REC_FLIP)
      {
         if(!safety.CanExecuteRecovery(nextLevel, true))
            return;

         LogAction("MEMICU FLIP MARTINGALE: " + liveDec.summaryReason);
         m_isFlipClosing = true;
         bool closedOK   = ClosePositions(openDir);
         m_isFlipClosing = false;
         if(!closedOK)
         {
            Print("[GT Recovery Engine][WARN] Tidak semua posisi lama berhasil ditutup; menunda Flip.");
            return;
         }

         double execPx = 0.0, execLot = 0.0;
         string reasonAdvFlip = StringFormat("Adv%.0fp|", adversePips) + liveDec.activeReversalFactors;
         string tag = MakeComment(StringFormat("GT_FLIP_L%d", nextLevel), reasonAdvFlip);
         if(SendMarketOrder(liveDec.recommendedDir, nextLot, true, pipConv, ind, tag, execPx, execLot))
         {
            m_state.cycleActive         = true;
            m_state.flipCycleLocked     = true;
            m_state.currentDir          = liveDec.recommendedDir;
            m_state.currentLevel        = nextLevel;
            m_state.lastMode            = GT_REC_FLIP;
            m_state.lastEntryPrice      = execPx;
            m_state.lastLot             = execLot;
            m_state.lastActionBarTime   = curBarTime;
            m_state.pendingPostSLReEval = false;
            m_state.lastEntryReason     = reasonAdvFlip;
            if(m_state.cycleSLDistPx <= 0.0)
               m_state.cycleSLDistPx = m_lastSLDistPx;
            m_state.flipCount++;
         }
      }
      else if(liveDec.mode == GT_REC_CLASSIC)
      {
         if(!liveDec.allowExecution)
            return;
         if(!safety.CanExecuteRecovery(nextLevel, false))
            return;

         double execPx = 0.0, execLot = 0.0;
         string reasonAdvClassic = StringFormat("Grid%.0fp|Kont%d", adversePips, liveDec.continuationScore);
         string tag = MakeComment(StringFormat("GT_CLASSIC_L%d", nextLevel), reasonAdvClassic);
         if(SendMarketOrder(openDir, nextLot, m_state.flipCycleLocked, pipConv, ind, tag, execPx, execLot))
         {
            m_state.cycleActive         = true;
            m_state.currentDir          = openDir;
            m_state.currentLevel        = nextLevel;
            m_state.lastMode            = GT_REC_CLASSIC;
            m_state.lastEntryPrice      = execPx;
            m_state.lastLot             = execLot;
            m_state.lastActionBarTime   = curBarTime;
            m_state.pendingPostSLReEval = false;
            m_state.lastEntryReason     = reasonAdvClassic;
            m_state.classicCount++;

            LogAction("MARTINGALE KLASIK: " + liveDec.summaryReason);
            AlignClassicBasketTP(openDir, pipConv);
         }
      }
   }
};

#define GT_BTN_EMERGENCY  (GT_OBJ_PREFIX + "BTN_EMERG")

//+------------------------------------------------------------------+
//| CSimulatorPanel                                                  |
//+------------------------------------------------------------------+
class CSimulatorPanel
{
private:
   bool              m_enabled;
   int               m_x;
   int               m_y;
   int               m_width;
   int               m_panelHeight;
   bool              m_created;
   SSimulatorMetrics m_metrics;

   void CreateRect(const string name,
                   const int x, const int y,
                   const int w, const int h,
                   const color bgColor,
                   const color borderColor,
                   const int borderWidth = 1) const
   {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);

      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(0, name, OBJPROP_COLOR, borderColor);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, borderWidth);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   void SetLabel(const string name,
                 const int x, const int y,
                 const string text,
                 const color clr,
                 const int fontSize = 9,
                 const string font = "Consolas") const
   {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, font);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   void CreateButton(const string name,
                     const int x, const int y,
                     const int w, const int h,
                     const string text,
                     const color txtColor,
                     const color bgColor,
                     const color borderColor) const
   {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderColor);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   string TruncateText(const string src, const int maxLen) const
   {
      if(StringLen(src) <= maxLen) return src;
      return StringSubstr(src, 0, maxLen - 3) + "...";
   }

public:
   CSimulatorPanel()
   {
      m_enabled     = true;
      m_x           = 14;
      m_y           = 24;
      m_width       = 410;
      m_panelHeight = 528;
      m_created     = false;
      m_metrics.Reset();
   }

   void Init(const bool enabled, const int x = 14, const int y = 24)
   {
      m_enabled = enabled && !MQLInfoInteger(MQL_OPTIMIZATION);
      m_x       = x;
      m_y       = y;
      m_created = false;
      m_metrics.Reset();
   }

   void Destroy()
   {
      ObjectsDeleteAll(0, GT_OBJ_PREFIX);
      m_created = false;
      ChartRedraw(0);
   }

   SSimulatorMetrics GetMetrics() const
   {
      return m_metrics;
   }

   SSimulatorMetrics CalculateSimulation(const CPipConverter &pipConv,
                                         const double initialLot,
                                         const double multiplier,
                                         const int    maxLevel,
                                         const double gridStepPips,
                                         const ENUM_GT_SLTP_MODE sltpMode,
                                         const double fixedSLPips,
                                         const double fixedTPPips,
                                         const double rrRatio)
   {
      SSimulatorMetrics m;
      m.Reset();

      m.balance        = AccountInfoDouble(ACCOUNT_BALANCE);
      m.equity         = AccountInfoDouble(ACCOUNT_EQUITY);
      m.initialLot     = pipConv.NormalizeLot(initialLot);
      m.multiplier     = multiplier;
      m.maxLevel       = MathMax(0, maxLevel);
      m.gridStepPips   = gridStepPips;
      m.rrRatio        = rrRatio;
      m.pipValuePerLot = pipConv.GetPipValuePerLot();

      m.slPips = (fixedSLPips > 0.0) ? fixedSLPips : gridStepPips;
      if(sltpMode == GT_SLTP_RISK_REWARD)
         m.tpPips = m.slPips * rrRatio;
      else if(sltpMode == GT_SLTP_FIXED_PIP)
         m.tpPips = (fixedTPPips > 0.0) ? fixedTPPips : (m.slPips * rrRatio);
      else
         m.tpPips = (fixedTPPips > 0.0) ? fixedTPPips : (m.slPips * rrRatio);

      double levelLots[];
      ArrayResize(levelLots, m.maxLevel + 1);

      double curLot   = m.initialLot;
      double totalExp = 0.0;

      for(int lv = 0; lv <= m.maxLevel; lv++)
      {
         if(lv == 0)
            curLot = m.initialLot;
         else
            curLot = pipConv.CalcNextRecoveryLot(curLot, m.multiplier);

         levelLots[lv] = curLot;
         totalExp     += curLot;
      }

      m.totalExposureLots = totalExp;
      m.maxSingleLevelLot = levelLots[m.maxLevel];

      double classicDDMoney = 0.0;
      double weightedDist   = 0.0;
      double flipDDMoney    = 0.0;

      for(int lv = 0; lv <= m.maxLevel; lv++)
      {
         double distFromLastEntryPips = (double)(m.maxLevel - lv) * m.gridStepPips;
         double worstAdversePips      = distFromLastEntryPips + m.slPips;

         classicDDMoney += levelLots[lv] * worstAdversePips * m.pipValuePerLot;
         weightedDist   += levelLots[lv] * distFromLastEntryPips;
         flipDDMoney    += levelLots[lv] * m.slPips * m.pipValuePerLot;
      }

      m.estClassicDrawdownMoney = classicDDMoney;
      m.estFlipDrawdownMoney    = flipDDMoney;

      if(m.balance > 0.0)
      {
         m.estClassicDrawdownPct = (classicDDMoney / m.balance) * 100.0;
         m.estFlipDrawdownPct    = (flipDDMoney / m.balance) * 100.0;
      }

      double avgDistToBEPips = (totalExp > 0.0) ? (weightedDist / totalExp) : 0.0;
      m.targetRecoveryPips   = avgDistToBEPips + m.tpPips;
      m.targetRecoveryMoney  = totalExp * m.tpPips * m.pipValuePerLot;

      m_metrics = m;
      return m;
   }

   void Render(const CPipConverter &pipConv,
               const SIndicatorData &ind,
               const SMarketContext &ctx,
               const SProbabilityDecision &dec,
               const SRecoveryState &state,
               const SSafetyStatus &safety,
               const string validationWarning,
               const string signalSourceLabel = "ALL-IN-ONE")
   {
      if(!m_enabled)
         return;

      string cur = AccountInfoString(ACCOUNT_CURRENCY);
      if(cur == "") cur = "USD";

      color bgMain     = C'14,20,30';
      color bgHeader   = C'22,34,54';
      color bgSection  = C'18,27,42';
      color borderClr  = C'44,66,96';
      color clrTitle   = C'240,196,74';
      color clrAccent  = C'86,196,245';
      color clrText    = C'226,232,240';
      color clrMuted   = C'148,163,184';
      color colGreen   = C'52,211,153';
      color colRed     = C'248,113,113';
      color colAmber   = C'251,191,36';

      int x = m_x;
      int y = m_y;
      int w = m_width;

      CreateRect(GT_OBJ_PREFIX + "BG", x, y, w, m_panelHeight, bgMain, borderClr, 1);
      CreateRect(GT_OBJ_PREFIX + "HDR", x, y, w, 30, bgHeader, borderClr, 1);
      SetLabel(GT_OBJ_PREFIX + "TITLE", x + 10, y + 7,
               "GT RECOVERY ENGINE  |  ICT + SMC + CRT", clrTitle, 10, "Segoe UI Bold");

      int secGap = 6;
      int lh     = 16;

      //--- SECTION 1: RECOVERY SIMULATOR
      int sec1Y = y + 36;
      int sec1H = 158;
      CreateRect(GT_OBJ_PREFIX + "SEC1", x + 8, sec1Y, w - 16, sec1H, bgSection, borderClr, 1);
      SetLabel(GT_OBJ_PREFIX + "S1_HDR", x + 16, sec1Y + 5,
               "RECOVERY SIMULATOR (AUTO)", clrAccent, 8, "Segoe UI Bold");
      int rowY = sec1Y + 22;

      SetLabel(GT_OBJ_PREFIX + "SIM_BAL", x + 16, rowY,
               StringFormat("Balance         : %10.2f %s", m_metrics.balance, cur), clrText, 8);
      rowY += lh;
      SetLabel(GT_OBJ_PREFIX + "SIM_EQ", x + 16, rowY,
               StringFormat("Equity          : %10.2f %s", m_metrics.equity, cur),
               (m_metrics.equity >= m_metrics.balance ? colGreen : colAmber), 8);
      rowY += lh;
      SetLabel(GT_OBJ_PREFIX + "SIM_LOT", x + 16, rowY,
               StringFormat("Lot Awal / Mult : %.2f lot  |  %.2fx  |  Max Lv %d",
                            m_metrics.initialLot, m_metrics.multiplier, m_metrics.maxLevel), clrText, 8);
      rowY += lh;
      SetLabel(GT_OBJ_PREFIX + "SIM_GRID", x + 16, rowY,
               StringFormat("Grid Step / RR  : %.1f pip  |  RR 1:%.2f (SL %.0f / TP %.0f)",
                            m_metrics.gridStepPips, m_metrics.rrRatio, m_metrics.slPips, m_metrics.tpPips), clrText, 8);
      rowY += lh;
      SetLabel(GT_OBJ_PREFIX + "SIM_EXP", x + 16, rowY,
               StringFormat("Total Exposure  : %.2f lot (MaxLv Lot: %.2f)",
                            m_metrics.totalExposureLots, m_metrics.maxSingleLevelLot), colAmber, 8);
      rowY += lh;
      SetLabel(GT_OBJ_PREFIX + "SIM_DD1", x + 16, rowY,
               StringFormat("Est. DD Klasik  : -%.2f %s (%.1f%% Bal)",
                            m_metrics.estClassicDrawdownMoney, cur, m_metrics.estClassicDrawdownPct),
               (m_metrics.estClassicDrawdownPct > 30.0 ? colRed : colAmber), 8);
      rowY += lh;
      SetLabel(GT_OBJ_PREFIX + "SIM_DD2", x + 16, rowY,
               StringFormat("Est. DD Flip    : -%.2f %s (%.1f%% Bal)",
                            m_metrics.estFlipDrawdownMoney, cur, m_metrics.estFlipDrawdownPct), clrMuted, 8);
      rowY += lh;
      SetLabel(GT_OBJ_PREFIX + "SIM_TGT", x + 16, rowY,
               StringFormat("Target Recovery : +%.2f %s (%.1f pip BE+TP)",
                            m_metrics.targetRecoveryMoney, cur, m_metrics.targetRecoveryPips), colGreen, 8);

      //--- SECTION 2: AUTO PIP & SIGNAL ENGINE
      int sec2Y = sec1Y + sec1H + secGap;
      int sec2H = 94;
      CreateRect(GT_OBJ_PREFIX + "SEC2", x + 8, sec2Y, w - 16, sec2H, bgSection, borderClr, 1);
      SetLabel(GT_OBJ_PREFIX + "S2_HDR", x + 16, sec2Y + 5,
               StringFormat("AUTO PIP & ICT_SMC_CRT [%s]", signalSourceLabel), clrAccent, 8, "Segoe UI Bold");
      rowY = sec2Y + 22;

      SetLabel(GT_OBJ_PREFIX + "PIP_INFO", x + 16, rowY,
               StringFormat("Asset: %s | Digits:%d | 1 Pip=%.0f pts ($%.2f/lot)",
                            pipConv.GetAssetClassName(), pipConv.Digits(),
                            pipConv.PointsPerPip(), m_metrics.pipValuePerLot), clrText, 8);
      rowY += lh;

      string sigStr = "NONE";
      if(ind.buySignal && ind.sellSignal) sigStr = "BOTH (CONFLICT)";
      else if(ind.buySignal)              sigStr = "BUY ACTIVE";
      else if(ind.sellSignal)             sigStr = "SELL ACTIVE";

      color biasClr = (ind.bias == GT_BIAS_BULLISH) ? colGreen :
                      ((ind.bias == GT_BIAS_BEARISH) ? colRed : clrMuted);
      SetLabel(GT_OBJ_PREFIX + "IND_BIAS", x + 16, rowY,
               StringFormat("Bias: %-12s | Sig: %-11s | KZ: %s",
                            GT_BiasToString(ind.bias), sigStr, ctx.killZoneName), biasClr, 8);
      rowY += lh;

      string zoneStr = ctx.inDiscount ? (ctx.inBullOTE ? "DISCOUNT+OTE" : "DISCOUNT")
                                      : (ctx.inBearOTE ? "PREMIUM+OTE"  : "PREMIUM");
      SetLabel(GT_OBJ_PREFIX + "CTX_ZONE", x + 16, rowY,
               StringFormat("Zona: %-12s | CRT: %s | EQ50: %s",
                            zoneStr,
                            ctx.crtBull ? "BULL" : (ctx.crtBear ? "BEAR" : "-"),
                            DoubleToString(ctx.eq50, pipConv.Digits())), clrMuted, 8);
      rowY += lh;

      SetLabel(GT_OBJ_PREFIX + "SIG_INFO", x + 16, rowY,
               TruncateText("Sinyal: " + ind.signalReason, 54),
               (ind.buySignal ? colGreen : (ind.sellSignal ? colRed : clrMuted)), 8);

      //--- SECTION 3: PROBABILITY & RECOVERY
      int sec3Y = sec2Y + sec2H + secGap;
      int sec3H = 126;
      CreateRect(GT_OBJ_PREFIX + "SEC3", x + 8, sec3Y, w - 16, sec3H, bgSection, borderClr, 1);
      SetLabel(GT_OBJ_PREFIX + "S3_HDR", x + 16, sec3Y + 5,
               "PROBABILITY & RECOVERY ENGINE", clrAccent, 8, "Segoe UI Bold");
      rowY = sec3Y + 22;

      color modeClr = (state.lastMode == GT_REC_FLIP || state.flipCycleLocked) ? colAmber :
                      ((state.lastMode == GT_REC_CLASSIC) ? clrAccent : clrMuted);
      string flipLockTag = state.flipCycleLocked ? " [WAJIB TP]" : "";
      SetLabel(GT_OBJ_PREFIX + "REC_MODE", x + 16, rowY,
               StringFormat("Mode: %s (Lv%d %s)%s",
                            GT_RecoveryModeToString(state.lastMode),
                            state.currentLevel, GT_DirToString(state.currentDir),
                            flipLockTag), modeClr, 8);
      rowY += lh;

      SetLabel(GT_OBJ_PREFIX + "REC_POS", x + 16, rowY,
               StringFormat("Open Pos: %d | Float P/L: %+.2f %s | Cycle: %+.2f",
                            safety.currentOpenPositions, safety.currentFloatingPL, cur, state.realizedCyclePL),
               (safety.currentFloatingPL >= 0.0 ? colGreen : colRed), 8);
      rowY += lh;

      color scoreClr = (dec.reversalScore > dec.threshold && dec.threshold > 0) ? colAmber : clrText;
      SetLabel(GT_OBJ_PREFIX + "PROB_SCR", x + 16, rowY,
               StringFormat("Skor Reversal: %d / Thresh %d  |  Kontinuasi: %d",
                            dec.reversalScore, dec.threshold, dec.continuationScore), scoreClr, 8);
      rowY += lh;

      SetLabel(GT_OBJ_PREFIX + "PROB_TIER", x + 16, rowY,
               StringFormat("Hierarki Flip: %s | Struktur: %s",
                            GT_TierToString(dec.highestTier),
                            dec.structureIntact ? "UTUH" : "BERUBAH"), clrText, 8);
      rowY += lh;

      SetLabel(GT_OBJ_PREFIX + "PROB_FAC1", x + 16, rowY,
               TruncateText("Rev : " + dec.activeReversalFactors, 54), colAmber, 8);
      rowY += lh;

      SetLabel(GT_OBJ_PREFIX + "PROB_FAC2", x + 16, rowY,
               TruncateText("Kont: " + dec.activeContinuationFactors, 54), clrMuted, 8);

      //--- SECTION 4: SAFETY + EMERGENCY BUTTON
      int sec4Y = sec3Y + sec3H + secGap;
      int sec4H = 88;
      color sec4Border = safety.tradingHalted ? colRed : (validationWarning != "" ? colAmber : borderClr);
      color sec4Bg     = safety.tradingHalted ? C'55,18,22' : bgSection;
      CreateRect(GT_OBJ_PREFIX + "SEC4", x + 8, sec4Y, w - 16, sec4H, sec4Bg, sec4Border, 1);

      string safetyHdr = safety.tradingHalted ? "SAFETY ALERT - TRADING DIHENTIKAN!" : "SAFETY SHIELD: NORMAL";
      SetLabel(GT_OBJ_PREFIX + "S4_HDR", x + 16, sec4Y + 5,
               safetyHdr, safety.tradingHalted ? colRed : colGreen, 8, "Segoe UI Bold");
      rowY = sec4Y + 22;

      SetLabel(GT_OBJ_PREFIX + "SAFE_DD", x + 16, rowY,
               StringFormat("Daily DD: %.2f%% | %s",
                            safety.currentDailyDDPct,
                            TruncateText(safety.haltReason, 40)),
               safety.tradingHalted ? colRed : clrText, 8);
      rowY += lh;

      string warnText = (validationWarning != "") ? TruncateText(validationWarning, 54)
                                                  : "Validasi Pip & RR: OK";
      SetLabel(GT_OBJ_PREFIX + "WARN_TXT", x + 16, rowY,
               warnText, (validationWarning != "" ? colAmber : colGreen), 8);
      rowY += lh + 4;

      string btnText = safety.emergencyActive ? "RESUME ENGINE (EMERGENCY ACTIVE)" : "EMERGENCY STOP";
      color  btnBg   = safety.emergencyActive ? C'180,40,40' : C'120,30,36';
      CreateButton(GT_BTN_EMERGENCY, x + 16, rowY, w - 32, 22, btnText, clrWhite, btnBg, colRed);

      m_created = true;
      ChartRedraw(0);
   }
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== 1. Sumber Sinyal ICT + SMC + CRT (All-in-One Default) ==="
input ENUM_GT_SIGNAL_SOURCE     InpSignalSource         = GT_SRC_INTERNAL_ALL_IN_ONE; // Mode Sumber Sinyal (Default: All-in-One 1 File)
input ENUM_TIMEFRAMES           InpIndTimeframe         = PERIOD_CURRENT;             // Timeframe Sinyal & Struktur
input int                       InpSignalShift          = 1;                          // Shift Bar Sinyal (1=Closed Bar, 0=Live)
input ENUM_GT_ENTRY_SENSITIVITY InpEntrySensitivity     = GT_SENS_BALANCED;           // Sensitivitas Entry All-in-One
input double                    InpStructSLBufferPips   = 3.0;                        // Buffer SL Struktural All-in-One (Pip)
input bool                      InpDrawChartVisuals     = true;                       // Gambar Sinyal & Level EQ50/CRT di Chart
input string                    InpIndicatorName        = "ICT_SMC_CRT";              // Nama Indikator Eksternal (Khusus Mode iCustom)

input group "=== 2. Entry Engine, SL/TP & Risk Reward ==="
input double                  InpInitialLot             = 0.01;              // Lot Awal
input ENUM_GT_SLTP_MODE       InpSLTPMode               = GT_SLTP_INDICATOR; // Mode SL & TP
input ENUM_GT_RR_MODE         InpRRMode                 = GT_RR_1_2;         // Preset Risk Reward (RR)
input double                  InpCustomRR               = 2.0;               // Custom RR (jika Mode RR = Custom)
input double                  InpFixedSLPips            = 20.0;              // SL Fixed / Basis RR / Fallback (Pip)
input double                  InpFixedTPPips            = 40.0;              // TP Fixed / Fallback Indikator (Pip)
input bool                    InpOnlyEntryInKillZone    = false;             // Entry Awal Hanya Saat KillZone
input double                  InpMaxSpreadPips          = 0.0;               // Spread Maksimal dalam Pip (0 = Off)
input bool                    InpRejectInvalidIndTP     = true;              // Tolak Order jika TP Indikator < Grid Step (Flip tidak pernah ditolak)
input bool                    InpStrictRRValidation     = false;             // Tolak Init/Order jika RR Tidak Sesuai (False=Warning)
input bool                    InpEnforceExactRR         = true;              // Kunci Presisi Rasio SL:TP Sesuai RR (1:2 Tepat)
input bool                    InpCommentEntryReason     = true;              // [v1.33] Tulis Alasan Entry di Komentar Order MT5

input group "=== 3. Recovery Engine (Direct Flip / Hybrid / Martingale Klasik) ==="
input ENUM_GT_FLIP_EXEC_MODE  InpFlipExecMode           = GT_FLIP_DIRECT_ON_SL; // Mode Eksekusi Flip (Default: Direct Flip Saat SL)
input bool                    InpFlipInheritSL          = true;                 // [v1.33] Flip Pakai Jarak SL Sama dengan Entry Awal (RR Presisi)
input ENUM_GT_GRID_STEP       InpGridStepMode           = GT_GRID_20_PIP;       // Pilihan Grid Step
input double                  InpCustomGridStepPips     = 25.0;                 // Custom Grid Step (Pip)
input ENUM_GT_LOT_MULT        InpMultiplierMode         = GT_MULT_1_5;          // Pilihan Multiplier Lot
input double                  InpCustomMultiplier       = 1.6;                  // Custom Multiplier Lot
input ENUM_GT_CLASSIC_TP_MODE InpClassicTPMode          = GT_CLASSIC_TP_BASKET; // Mode TP Martingale Klasik
input bool                    InpEnablePostSLRecovery   = true;                 // Evaluasi Ulang Otomatis Setelah SL Terkena
input bool                    InpFlipMustEndInTP        = true;                 // Flip Wajib Tuntas TP Sebelum Cari Sinyal Baru
input bool                    InpFlipAutoCoverLossTP    = false;                // Auto Perpanjang TP Flip (False = Jaga RR 1:2 Presisi)
input bool                    InpRequireIntactForClassic= false;                // Wajib Struktur Utuh (No Opp CHoCH/BOS) untuk Klasik

input group "=== 4. Sistem Skor Probabilitas (Flip vs Klasik) ==="
input bool                    InpUseScoreSystem         = true;              // Aktifkan Sistem Skor (False = Mode Hierarki Tier)
input int                     InpFlipScoreThreshold     = 8;                 // Ambang Batas Skor Reversal (> Threshold = FLIP)
input int                     InpW_IDM                  = 5;                 // Bobot IDM Sweep (Tier 1)
input int                     InpW_xSSL                 = 4;                 // Bobot xSSL (Tier 1)
input int                     InpW_xBSL                 = 4;                 // Bobot xBSL (Tier 1)
input int                     InpW_CHoCH                = 4;                 // Bobot CHoCH (Tier 1)
input int                     InpW_CRT                  = 4;                 // Bobot CRT Reverse (Tier 1)
input int                     InpW_IFVG                 = 3;                 // Bobot IFVG (Tier 2)
input int                     InpW_FVG                  = 3;                 // Bobot FVG Lawan Arah
input int                     InpW_OB                   = 2;                 // Bobot OB Lawan Arah
input int                     InpW_BOS                  = 2;                 // Bobot BOS Lawan Arah (Tier 3)
input int                     InpW_iCHoCH               = 1;                 // Bobot iCHoCH (Tier 3)
input int                     InpW_iBOS                 = 1;                 // Bobot iBOS (Tier 3)
input int                     InpW_OTE                  = 1;                 // Bobot OTE
input int                     InpW_Discount             = 1;                 // Bobot Discount (Flip Bullish)
input int                     InpW_Premium              = 1;                 // Bobot Premium (Flip Bearish)

input group "=== 4B. Bobot Konfluensi Institusional Tambahan ==="
input int                     InpW_Sweep                = 1;                 // Bobot Sweep Umum
input int                     InpW_EQH_EQL              = 1;                 // Bobot EQH / EQL Sweep
input int                     InpW_Breaker              = 2;                 // Bobot Breaker Block
input int                     InpW_MB_VI_Void           = 1;                 // Bobot MB / VI / Liquidity Void
input int                     InpW_HTF_Liq              = 1;                 // Bobot Sweep PDH / PDL / PWH / PWL
input int                     InpW_KillZone             = 1;                 // Bobot Bonus KillZone Aktif
input int                     InpW_IndBiasFlip          = 3;                 // Bobot Perubahan Bias / Sinyal Lawan ICT_SMC_CRT

input group "=== 5. Struktur Pasar ICT + SMC + CRT & KillZone ==="
input ENUM_TIMEFRAMES         InpCRTTF                  = PERIOD_H1;         // Timeframe Candle Range Theory (CRT)
input int                     InpExtSwingStrength       = 5;                 // Kekuatan Fractal Swing Eksternal (BOS/CHoCH)
input int                     InpIntSwingStrength       = 2;                 // Kekuatan Fractal Swing Internal (iBOS/iCHoCH/IDM)
input int                     InpStructureLookback      = 140;               // Jumlah Bar Lookback Struktur
input int                     InpSignalWindowBars       = 8;                 // Jendela Bar Aktif Sinyal Reversal
input double                  InpEQTolerancePips        = 3.0;               // Toleransi EQH / EQL (Pip)
input double                  InpMinFVGPips             = 1.0;               // Ukuran Minimal FVG / IFVG (Pip)
input bool                    InpUseAsiaKZ              = false;             // Aktifkan Asia KillZone
input string                  InpAsiaKZTime             = "01:00-08:00";     // Waktu Asia KZ (Server Broker)
input bool                    InpUseLondonKZ            = true;              // Aktifkan London KillZone
input string                  InpLondonKZTime           = "09:00-12:00";     // Waktu London KZ (Server Broker)
input bool                    InpUseNYAMKZ              = true;              // Aktifkan New York AM KillZone
input string                  InpNYAMKZTime             = "15:00-18:00";     // Waktu NY AM KZ (Server Broker)
input bool                    InpUseNYPMKZ              = true;              // Aktifkan New York PM KillZone
input string                  InpNYPMKZTime             = "21:00-22:00";     // Waktu NY PM KZ (Server Broker)

input group "=== 6. Auto Pip Converter ==="
input ENUM_GT_ASSET_CLASS     InpAssetClass             = GT_ASSET_AUTO;     // Deteksi Jenis Instrumen
input double                  InpCustomPipSize          = 0.0;               // Custom Pip Size (khusus mode Custom)

input group "=== 7. Safety & Proteksi Akun ==="
input int                     InpMaxMartingaleLevel     = 5;                 // Max Martingale Level
input ENUM_GT_LOSS_MODE       InpFloatingLossMode       = GT_LOSS_PERCENT;   // Satuan Max Floating Loss
input double                  InpMaxFloatingLoss        = 15.0;              // Max Floating Loss (0 = Nonaktif)
input double                  InpMaxDailyDrawdownPct    = 5.0;               // Max Daily Drawdown % Balance (0 = Nonaktif)
input int                     InpMaxOpenPositions       = 6;                 // Max Open Positions
input bool                    InpEmergencyStop          = false;             // Emergency Stop (Hentikan Semua Aktivitas)
input bool                    InpCloseAllOnEmergency    = false;             // Tutup Semua Posisi Saat Emergency Stop Aktif

input group "=== 7B. Resume Setelah Daily Drawdown (v1.32) ==="
input bool                    InpDDResumeOnSignal       = true;              // Setelah DD Tercapai: Entry Lagi pada Sinyal Berikutnya (Tanpa Tunggu Hari Baru)
input int                     InpMaxDDResumePerDay      = 0;                 // Batas Resume DD per Hari (0 = Tanpa Batas)
input bool                    InpAbandonCycleOnHalt     = true;              // Batalkan Siklus Flip yang Macet (DD / Max Level) lalu Mulai Lagi dari L0

input group "=== 8. Panel Simulator & Pengaturan Umum ==="
input bool                    InpShowPanel              = true;              // Tampilkan Panel Recovery Simulator
input int                     InpPanelX                 = 14;                // Posisi X Panel
input int                     InpPanelY                 = 24;                // Posisi Y Panel
input long                    InpMagicNumber            = 20261121;          // Magic Number EA
input int                     InpSlippagePoints         = 20;                // Slippage Maksimal (Points)
input bool                    InpEnableAlerts           = true;              // Aktifkan Pop-Up Alert

//+------------------------------------------------------------------+
//| GLOBAL MODULE INSTANCES                                          |
//+------------------------------------------------------------------+
CPipConverter      g_pipConv;
CIndicatorBridge   g_indBridge;
CMarketStructure   g_structure;
CProbabilityEngine g_probEngine;
CSafetyManager     g_safety;
CRecoveryEngine    g_engine;
CSimulatorPanel    g_panel;

double             g_gridStepPips     = 20.0;
double             g_multiplier       = 1.5;
double             g_rrRatio          = 2.0;
string             g_initWarning      = "";
datetime           g_lastStructBar    = 0;
datetime           g_lastPanelRefresh = 0;

//+------------------------------------------------------------------+
//| Helper: Refresh Simulator Calculation & Panel UI                 |
//+------------------------------------------------------------------+
void UpdateDashboard(const SIndicatorData &ind,
                     const SMarketContext &ctx)
{
   if(!InpShowPanel || MQLInfoInteger(MQL_OPTIMIZATION))
      return;

   g_panel.CalculateSimulation(g_pipConv,
                               InpInitialLot,
                               g_multiplier,
                               InpMaxMartingaleLevel,
                               g_gridStepPips,
                               InpSLTPMode,
                               InpFixedSLPips,
                               InpFixedTPPips,
                               g_rrRatio);

   string warn = g_initWarning;
   string rtWarn = g_engine.GetRuntimeWarning();
   if(rtWarn != "")
      warn = rtWarn;

   g_panel.Render(g_pipConv,
                  ind,
                  ctx,
                  g_probEngine.GetLastDecision(),
                  g_engine.GetState(),
                  g_safety.GetStatus(),
                  warn,
                  g_indBridge.GetSourceLabel());
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_initWarning      = "";
   g_lastStructBar    = 0;
   g_lastPanelRefresh = 0;

   if(!g_pipConv.Init(_Symbol, InpAssetClass, InpCustomPipSize))
   {
      Print("[GT Recovery Engine][ERROR] Gagal inisialisasi Auto Pip Converter untuk ", _Symbol);
      return INIT_FAILED;
   }

   g_gridStepPips = GT_ResolveGridStepPips(InpGridStepMode, InpCustomGridStepPips);
   g_multiplier   = GT_ResolveMultiplier(InpMultiplierMode, InpCustomMultiplier);
   g_rrRatio      = GT_ResolveRR(InpRRMode, InpCustomRR);

   SValidationResult vr = CConfigValidator::ValidateInit(g_pipConv,
                                                         InpSLTPMode,
                                                         InpRRMode,
                                                         InpCustomRR,
                                                         InpFixedSLPips,
                                                         InpFixedTPPips,
                                                         g_gridStepPips,
                                                         InpInitialLot,
                                                         g_multiplier,
                                                         InpMaxMartingaleLevel,
                                                         InpMaxOpenPositions,
                                                         InpStrictRRValidation);
   if(!vr.isValid)
   {
      Print("[GT Recovery Engine][CONFIG REJECTED] ", vr.errorMessage);
      if(InpEnableAlerts && !MQLInfoInteger(MQL_OPTIMIZATION))
         Alert("[GT Recovery Engine] ", vr.errorMessage);
      Comment("GT RECOVERY ENGINE - KONFIGURASI DITOLAK:\n", vr.errorMessage);
      return INIT_PARAMETERS_INCORRECT;
   }

   if(vr.hasWarning)
   {
      g_initWarning = vr.warningMessage;
      Print("[GT Recovery Engine] ", vr.warningMessage);
      if(InpEnableAlerts && !MQLInfoInteger(MQL_OPTIMIZATION))
         Alert("[GT Recovery Engine] ", vr.warningMessage);
   }

   ENUM_TIMEFRAMES workTF = (InpIndTimeframe == PERIOD_CURRENT) ? Period() : InpIndTimeframe;
   g_structure.Init(_Symbol,
                    workTF,
                    InpCRTTF,
                    InpExtSwingStrength,
                    InpIntSwingStrength,
                    InpStructureLookback,
                    InpSignalWindowBars,
                    InpEQTolerancePips,
                    InpMinFVGPips,
                    InpUseAsiaKZ,   InpAsiaKZTime,
                    InpUseLondonKZ, InpLondonKZTime,
                    InpUseNYAMKZ,   InpNYAMKZTime,
                    InpUseNYPMKZ,   InpNYPMKZTime);

   if(!g_indBridge.Init(InpSignalSource,
                        _Symbol,
                        workTF,
                        InpIndicatorName,
                        InpSignalShift,
                        InpEntrySensitivity,
                        InpStructSLBufferPips,
                        InpFixedSLPips,
                        g_rrRatio,
                        g_gridStepPips,
                        InpDrawChartVisuals))
   {
      if(InpEnableAlerts && !MQLInfoInteger(MQL_OPTIMIZATION))
         Alert("[GT Recovery Engine] ", g_indBridge.LastError());
      Comment("GT RECOVERY ENGINE - ERROR SUMBER SINYAL:\n", g_indBridge.LastError());
      return INIT_FAILED;
   }

   SScoreWeights w;
   w.enabled                        = InpUseScoreSystem;
   w.flipThreshold                  = InpFlipScoreThreshold;
   w.wIDM                           = InpW_IDM;
   w.wXSSL                          = InpW_xSSL;
   w.wXBSL                          = InpW_xBSL;
   w.wCHoCH                         = InpW_CHoCH;
   w.wCRT                           = InpW_CRT;
   w.wIFVG                          = InpW_IFVG;
   w.wFVG                           = InpW_FVG;
   w.wOB                            = InpW_OB;
   w.wBOS                           = InpW_BOS;
   w.wICHoCH                        = InpW_iCHoCH;
   w.wIBOS                          = InpW_iBOS;
   w.wOTE                           = InpW_OTE;
   w.wDiscount                      = InpW_Discount;
   w.wPremium                       = InpW_Premium;
   w.wSweep                         = InpW_Sweep;
   w.wEQH_EQL                       = InpW_EQH_EQL;
   w.wBreaker                       = InpW_Breaker;
   w.wMB_VI_Void                    = InpW_MB_VI_Void;
   w.wHTFLiq                        = InpW_HTF_Liq;
   w.wKillZone                      = InpW_KillZone;
   w.wIndBiasFlip                   = InpW_IndBiasFlip;
   w.requireIntactStructureForClassic = InpRequireIntactForClassic;
   g_probEngine.Configure(w);

   g_safety.Init(_Symbol,
                 InpMagicNumber,
                 InpMaxMartingaleLevel,
                 InpFloatingLossMode,
                 InpMaxFloatingLoss,
                 InpMaxDailyDrawdownPct,
                 InpMaxOpenPositions,
                 InpEmergencyStop,
                 InpCloseAllOnEmergency,
                 InpEnableAlerts);
   g_safety.ConfigureDDResume(InpDDResumeOnSignal, InpMaxDDResumePerDay);

   g_engine.Init(_Symbol,
                 workTF,
                 InpMagicNumber,
                 InpSlippagePoints,
                 InpInitialLot,
                 g_multiplier,
                 g_gridStepPips,
                 InpSLTPMode,
                 InpRRMode,
                 InpCustomRR,
                 InpFixedSLPips,
                 InpFixedTPPips,
                 InpClassicTPMode,
                 InpOnlyEntryInKillZone,
                 InpMaxSpreadPips,
                 InpRejectInvalidIndTP,
                 InpStrictRRValidation,
                 InpEnforceExactRR,
                 InpEnablePostSLRecovery,
                 InpFlipExecMode,
                 InpFlipMustEndInTP,
                 InpFlipAutoCoverLossTP,
                 InpEnableAlerts);
   g_engine.SetAbandonStuckCycle(InpAbandonCycleOnHalt);
   g_engine.SetFlipInheritSL(InpFlipInheritSL);              // v1.33
   g_engine.SetCommentEntryReason(InpCommentEntryReason);    // v1.33
   // Catatan: SyncFromOpenPositions() sudah dipanggil di Init(); setter di atas tidak memengaruhi sinkronisasi.

   g_panel.Init(InpShowPanel, InpPanelX, InpPanelY);

   g_structure.Update(g_pipConv);
   g_structure.UpdateLiveState(g_pipConv);

   SIndicatorData initInd;
   initInd.Reset();
   g_indBridge.Refresh(g_structure.GetContext(), g_pipConv, initInd);

   int openCnt = 0; double flt = 0.0, lots = 0.0, lPx = 0.0, lLot = 0.0;
   ENUM_GT_DIR dir = GT_DIR_NONE;
   g_engine.QueryPositions(openCnt, flt, lots, dir, lPx, lLot);
   g_safety.Update(g_engine.GetState().currentLevel, openCnt, flt, g_engine.GetState().pendingPostSLReEval);

   if(dir != GT_DIR_NONE)
      g_probEngine.Evaluate(dir, g_structure.GetContext(), initInd);
   else if(initInd.bias == GT_BIAS_BULLISH)
      g_probEngine.Evaluate(GT_DIR_BUY, g_structure.GetContext(), initInd);
   else if(initInd.bias == GT_BIAS_BEARISH)
      g_probEngine.Evaluate(GT_DIR_SELL, g_structure.GetContext(), initInd);

   Comment("");
   UpdateDashboard(initInd, g_structure.GetContext());

   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      EventSetTimer(1);

   PrintFormat("[GT Recovery Engine] SIAP v1.33 | Symbol=%s (%s, %d digits, 1 pip=%.0f pts) | Grid=%.1f pip | Mult=%.2fx | RR=1:%.2f | MaxLv=%d | DD Resume=%s | FlipInheritSL=%s",
               _Symbol, g_pipConv.GetAssetClassName(), g_pipConv.Digits(),
               g_pipConv.PointsPerPip(), g_gridStepPips, g_multiplier,
               g_rrRatio, InpMaxMartingaleLevel,
               InpDDResumeOnSignal ? "SINYAL BARU" : "HARI BERIKUTNYA",
               InpFlipInheritSL ? "ON" : "OFF");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_indBridge.Deinit();
   g_panel.Destroy();
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ENUM_TIMEFRAMES workTF = (InpIndTimeframe == PERIOD_CURRENT) ? Period() : InpIndTimeframe;

   datetime curBarTime = iTime(_Symbol, workTF, 0);
   if(curBarTime != g_lastStructBar)
   {
      if(g_structure.Update(g_pipConv))
         g_lastStructBar = curBarTime;
   }
   g_structure.UpdateLiveState(g_pipConv);

   SMarketContext ctx = g_structure.GetContext();

   SIndicatorData indData;
   g_indBridge.Refresh(ctx, g_pipConv, indData);

   g_engine.ProcessTick(g_pipConv, g_indBridge, indData, ctx, g_probEngine, g_safety);

   if(InpShowPanel && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      datetime now = TimeCurrent();
      if(now != g_lastPanelRefresh || !MQLInfoInteger(MQL_TESTER))
      {
         g_lastPanelRefresh = now;
         UpdateDashboard(indData, ctx);
      }
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   g_engine.OnDealTransaction(trans);
}

//+------------------------------------------------------------------+
//| Timer handler                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpShowPanel || MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER))
      return;

   int openCnt = 0; double flt = 0.0, lots = 0.0, lPx = 0.0, lLot = 0.0;
   ENUM_GT_DIR dir = GT_DIR_NONE;
   g_engine.QueryPositions(openCnt, flt, lots, dir, lPx, lLot);
   g_safety.Update(g_engine.GetState().currentLevel, openCnt, flt, g_engine.GetState().pendingPostSLReEval);

   UpdateDashboard(g_indBridge.GetLastData(), g_structure.GetContext());
}

//+------------------------------------------------------------------+
//| ChartEvent handler (Emergency Stop button toggle)                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == GT_BTN_EMERGENCY)
   {
      ObjectSetInteger(0, GT_BTN_EMERGENCY, OBJPROP_STATE, false);

      bool nextState = !g_safety.IsManualEmergencyActive();
      g_safety.TriggerManualEmergency(nextState);

      if(nextState)
      {
         Print("[GT Recovery Engine] EMERGENCY STOP diaktifkan manual dari panel chart.");
         if(g_safety.ShouldCloseAllOnEmergency())
            g_engine.ClosePositions(GT_DIR_NONE);
      }
      else
      {
         Print("[GT Recovery Engine] EMERGENCY STOP dinonaktifkan - Engine kembali aktif.");
         int openNow = 0; double fltNow = 0.0, lNow = 0.0, pNow = 0.0, lotNow = 0.0;
         ENUM_GT_DIR dNow = GT_DIR_NONE;
         g_engine.QueryPositions(openNow, fltNow, lNow, dNow, pNow, lotNow);
         if(openNow == 0)
            g_engine.ResetCycle();
      }

      int openCnt = 0; double flt = 0.0, lots = 0.0, lPx = 0.0, lLot = 0.0;
      ENUM_GT_DIR dir = GT_DIR_NONE;
      g_engine.QueryPositions(openCnt, flt, lots, dir, lPx, lLot);
      g_safety.Update(g_engine.GetState().currentLevel, openCnt, flt, g_engine.GetState().pendingPostSLReEval);
      UpdateDashboard(g_indBridge.GetLastData(), g_structure.GetContext());
   }
}
//+------------------------------------------------------------------+
