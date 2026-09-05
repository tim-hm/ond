# Copy audit coverage — 5 September 2026

Companion to the [complete source-copy audit](2026-09-05-complete-copy-audit.md), reviewed at `0b6a8ad2a`. This inventory defines coverage; a file listed here is not a claim that all of its runtime states were exercised.

## Method and exclusions

Screened every `.swift` file in the seven shipping native roots below. Read the string-literal candidate lines, then inspected surrounding code and data paths for findings. The screen includes comments, logs, raw values, asset keys and debug/preview text, which were distinguished from shipping UI copy. Interpolated phrases, error descriptions, accessibility labels and notification builders were included. Multiline literal blocks in these roots were also checked; the blocks found were subscription diagnostics.

- **C**: contains quoted literal candidates; candidate lines reviewed for user-facing wording. It does not mean every literal is user-facing.
- **N**: no quoted literal candidate; inventoried for completeness. Displayed values obtained from another file are covered at their source.
- Generated protobuf, package tests, UI fixtures, tooling commands, internal logs, asset names and third-party/OS-owned strings are not authored product copy. Custom OndAPI transport classification was checked separately below.
- Audio consists of cues rather than a recorded spoken script; haptic and sound setting/preview names are included in the native pass. Listening comfort and pronunciation were not tested here.
- No native localisation catalogue was found. This is an English source review, not a translated-language or locale/device acceptance pass.

## Native file inventory

| Root                 | Files screened | Files with literal candidates |
| -------------------- | -------------- | ----------------------------- |
| Ond                  | 134            | 104                           |
| OndActivity          | 9              | 7                             |
| OndWatch             | 23             | 20                            |
| OndWatchComplication | 2              | 1                             |
| OndKit               | 176            | 132                           |
| OndStyle             | 10             | 2                             |
| OndUI                | 23             | 5                             |
| Total                | 377            | 271                           |

### Ond

| Source                                                                                                               | Status |
| -------------------------------------------------------------------------------------------------------------------- | ------ |
| [Ond/AppConfiguration.swift](../../ios/Ond/AppConfiguration.swift)                                                   | C      |
| [Ond/CentredInScroller.swift](../../ios/Ond/CentredInScroller.swift)                                                 | N      |
| [Ond/Chrome/AppChrome.swift](../../ios/Ond/Chrome/AppChrome.swift)                                                   | C      |
| [Ond/Chrome/AppRoots.swift](../../ios/Ond/Chrome/AppRoots.swift)                                                     | C      |
| [Ond/Chrome/Appearance+ColorScheme.swift](../../ios/Ond/Chrome/Appearance+ColorScheme.swift)                         | N      |
| [Ond/CoachGlyph.swift](../../ios/Ond/CoachGlyph.swift)                                                               | C      |
| [Ond/DebugHostNote.swift](../../ios/Ond/DebugHostNote.swift)                                                         | N      |
| [Ond/DemoPractice.swift](../../ios/Ond/DemoPractice.swift)                                                           | C      |
| [Ond/EmptyCatalogueView.swift](../../ios/Ond/EmptyCatalogueView.swift)                                               | C      |
| [Ond/EvidenceChip.swift](../../ios/Ond/EvidenceChip.swift)                                                           | N      |
| [Ond/Features/Assistant/AssistantConsentView.swift](../../ios/Ond/Features/Assistant/AssistantConsentView.swift)     | C      |
| [Ond/Features/Assistant/BoltTestOfferCard.swift](../../ios/Ond/Features/Assistant/BoltTestOfferCard.swift)           | C      |
| [Ond/Features/Assistant/CoachChatView.swift](../../ios/Ond/Features/Assistant/CoachChatView.swift)                   | C      |
| [Ond/Features/Assistant/CoachComposer.swift](../../ios/Ond/Features/Assistant/CoachComposer.swift)                   | C      |
| [Ond/Features/Assistant/CoachGround.swift](../../ios/Ond/Features/Assistant/CoachGround.swift)                       | N      |
| [Ond/Features/Assistant/CoachOffer.swift](../../ios/Ond/Features/Assistant/CoachOffer.swift)                         | C      |
| [Ond/Features/Assistant/CoachRootView.swift](../../ios/Ond/Features/Assistant/CoachRootView.swift)                   | C      |
| [Ond/Features/Assistant/CoachTranscript.swift](../../ios/Ond/Features/Assistant/CoachTranscript.swift)               | C      |
| [Ond/Features/Assistant/ExerciseOfferCard.swift](../../ios/Ond/Features/Assistant/ExerciseOfferCard.swift)           | C      |
| [Ond/Features/Assistant/OfferCard.swift](../../ios/Ond/Features/Assistant/OfferCard.swift)                           | N      |
| [Ond/Features/Assistant/SavedExerciseOfferCard.swift](../../ios/Ond/Features/Assistant/SavedExerciseOfferCard.swift) | C      |
| [Ond/Features/Assistant/SuggestedForYouView.swift](../../ios/Ond/Features/Assistant/SuggestedForYouView.swift)       | C      |
| [Ond/Features/Assistant/ThinkingDot.swift](../../ios/Ond/Features/Assistant/ThinkingDot.swift)                       | C      |
| [Ond/Features/CheckIns/BoltTestView.swift](../../ios/Ond/Features/CheckIns/BoltTestView.swift)                       | C      |
| [Ond/Features/CheckIns/CheckInsView.swift](../../ios/Ond/Features/CheckIns/CheckInsView.swift)                       | C      |
| [Ond/Features/CheckIns/HealthTrendsCard.swift](../../ios/Ond/Features/CheckIns/HealthTrendsCard.swift)               | C      |
| [Ond/Features/CheckIns/RestingRateTestView.swift](../../ios/Ond/Features/CheckIns/RestingRateTestView.swift)         | C      |
| [Ond/Features/Foundations/FoundationsView.swift](../../ios/Ond/Features/Foundations/FoundationsView.swift)           | C      |
| [Ond/Features/Home/HomeChoiceSheet.swift](../../ios/Ond/Features/Home/HomeChoiceSheet.swift)                         | C      |
| [Ond/Features/Home/HomeView.swift](../../ios/Ond/Features/Home/HomeView.swift)                                       | C      |
| [Ond/Features/Leaderboard/BoardCard.swift](../../ios/Ond/Features/Leaderboard/BoardCard.swift)                       | C      |
| [Ond/Features/Leaderboard/LeaderboardFetch.swift](../../ios/Ond/Features/Leaderboard/LeaderboardFetch.swift)         | C      |
| [Ond/Features/Leaderboard/LeaderboardNameView.swift](../../ios/Ond/Features/Leaderboard/LeaderboardNameView.swift)   | C      |
| [Ond/Features/Leaderboard/LeaderboardView.swift](../../ios/Ond/Features/Leaderboard/LeaderboardView.swift)           | C      |
| [Ond/Features/Moments/MomentCard.swift](../../ios/Ond/Features/Moments/MomentCard.swift)                             | N      |
| [Ond/Features/Moments/MomentListView.swift](../../ios/Ond/Features/Moments/MomentListView.swift)                     | C      |
| [Ond/Features/Moments/StartableStopCard.swift](../../ios/Ond/Features/Moments/StartableStopCard.swift)               | C      |
| [Ond/Features/Moments/StopStarButton.swift](../../ios/Ond/Features/Moments/StopStarButton.swift)                     | C      |
| [Ond/Features/Onboarding/AmbientOrb.swift](../../ios/Ond/Features/Onboarding/AmbientOrb.swift)                       | C      |
| [Ond/Features/Onboarding/OnboardingChoice.swift](../../ios/Ond/Features/Onboarding/OnboardingChoice.swift)           | N      |
| [Ond/Features/Onboarding/OnboardingPickerRow.swift](../../ios/Ond/Features/Onboarding/OnboardingPickerRow.swift)     | N      |
| [Ond/Features/Onboarding/OnboardingQuestion.swift](../../ios/Ond/Features/Onboarding/OnboardingQuestion.swift)       | N      |
| [Ond/Features/Onboarding/OnboardingView.swift](../../ios/Ond/Features/Onboarding/OnboardingView.swift)               | C      |
| [Ond/Features/Onboarding/OptInsStepView.swift](../../ios/Ond/Features/Onboarding/OptInsStepView.swift)               | C      |
| [Ond/Features/Onboarding/SafetyConsentStepView.swift](../../ios/Ond/Features/Onboarding/SafetyConsentStepView.swift) | N      |
| [Ond/Features/Onboarding/SafetyConsentView.swift](../../ios/Ond/Features/Onboarding/SafetyConsentView.swift)         | N      |
| [Ond/Features/Onboarding/TrialStepView.swift](../../ios/Ond/Features/Onboarding/TrialStepView.swift)                 | N      |
| [Ond/Features/Onboarding/WelcomeStepView.swift](../../ios/Ond/Features/Onboarding/WelcomeStepView.swift)             | C      |
| [Ond/Features/Onboarding/YouStepView.swift](../../ios/Ond/Features/Onboarding/YouStepView.swift)                     | C      |
| [Ond/Features/Progress/PracticeChartView.swift](../../ios/Ond/Features/Progress/PracticeChartView.swift)             | C      |
| [Ond/Features/Progress/PracticeFigures.swift](../../ios/Ond/Features/Progress/PracticeFigures.swift)                 | C      |
| [Ond/Features/Progress/PracticeHeartCard.swift](../../ios/Ond/Features/Progress/PracticeHeartCard.swift)             | C      |
| [Ond/Features/Progress/PracticeProgressView.swift](../../ios/Ond/Features/Progress/PracticeProgressView.swift)       | C      |
| [Ond/Features/Progress/PracticeSummary.swift](../../ios/Ond/Features/Progress/PracticeSummary.swift)                 | C      |
| [Ond/Features/Progress/SessionDayHeader.swift](../../ios/Ond/Features/Progress/SessionDayHeader.swift)               | C      |
| [Ond/Features/Progress/SessionDayPlate.swift](../../ios/Ond/Features/Progress/SessionDayPlate.swift)                 | C      |
| [Ond/Features/Progress/SessionHistoryRow.swift](../../ios/Ond/Features/Progress/SessionHistoryRow.swift)             | C      |
| [Ond/Features/Progress/SessionHistoryView.swift](../../ios/Ond/Features/Progress/SessionHistoryView.swift)           | C      |
| [Ond/Features/Progress/SessionLegend.swift](../../ios/Ond/Features/Progress/SessionLegend.swift)                     | N      |
| [Ond/Features/Schedules/NotificationDelegate.swift](../../ios/Ond/Features/Schedules/NotificationDelegate.swift)     | N      |
| [Ond/Features/Schedules/NotificationScheduler.swift](../../ios/Ond/Features/Schedules/NotificationScheduler.swift)   | C      |
| [Ond/Features/Schedules/ScheduleEditorView.swift](../../ios/Ond/Features/Schedules/ScheduleEditorView.swift)         | C      |
| [Ond/Features/Schedules/SchedulesView.swift](../../ios/Ond/Features/Schedules/SchedulesView.swift)                   | C      |
| [Ond/Features/Session/AmbientField.swift](../../ios/Ond/Features/Session/AmbientField.swift)                         | N      |
| [Ond/Features/Session/BreathVisual.swift](../../ios/Ond/Features/Session/BreathVisual.swift)                         | C      |
| [Ond/Features/Session/CountdownView.swift](../../ios/Ond/Features/Session/CountdownView.swift)                       | C      |
| [Ond/Features/Session/CuePreviewView.swift](../../ios/Ond/Features/Session/CuePreviewView.swift)                     | C      |
| [Ond/Features/Session/HapticController.swift](../../ios/Ond/Features/Session/HapticController.swift)                 | C      |
| [Ond/Features/Session/MoodScale.swift](../../ios/Ond/Features/Session/MoodScale.swift)                               | C      |
| [Ond/Features/Session/PlayfulBreathVisual.swift](../../ios/Ond/Features/Session/PlayfulBreathVisual.swift)           | N      |
| [Ond/Features/Session/PulseBadge.swift](../../ios/Ond/Features/Session/PulseBadge.swift)                             | C      |
| [Ond/Features/Session/PulseCurve.swift](../../ios/Ond/Features/Session/PulseCurve.swift)                             | C      |
| [Ond/Features/Session/SessionAudioPlayer.swift](../../ios/Ond/Features/Session/SessionAudioPlayer.swift)             | C      |
| [Ond/Features/Session/SessionCues.swift](../../ios/Ond/Features/Session/SessionCues.swift)                           | C      |
| [Ond/Features/Session/SessionGround.swift](../../ios/Ond/Features/Session/SessionGround.swift)                       | N      |
| [Ond/Features/Session/SessionInvitationView.swift](../../ios/Ond/Features/Session/SessionInvitationView.swift)       | C      |
| [Ond/Features/Session/SessionOrb.swift](../../ios/Ond/Features/Session/SessionOrb.swift)                             | N      |
| [Ond/Features/Session/SessionPlayerView.swift](../../ios/Ond/Features/Session/SessionPlayerView.swift)               | C      |
| [Ond/Features/Session/SessionSlots.swift](../../ios/Ond/Features/Session/SessionSlots.swift)                         | N      |
| [Ond/Features/Session/SessionSoundStyle.swift](../../ios/Ond/Features/Session/SessionSoundStyle.swift)               | C      |
| [Ond/Features/Session/SessionSummaryView.swift](../../ios/Ond/Features/Session/SessionSummaryView.swift)             | C      |
| [Ond/Features/Session/SessionView.swift](../../ios/Ond/Features/Session/SessionView.swift)                           | C      |
| [Ond/Features/Session/SessionWords.swift](../../ios/Ond/Features/Session/SessionWords.swift)                         | C      |
| [Ond/Features/Session/StopLauncher.swift](../../ios/Ond/Features/Session/StopLauncher.swift)                         | N      |
| [Ond/Features/Session/TechniqueWarningView.swift](../../ios/Ond/Features/Session/TechniqueWarningView.swift)         | C      |
| [Ond/Features/Session/View+SpeaksPhase.swift](../../ios/Ond/Features/Session/View+SpeaksPhase.swift)                 | C      |
| [Ond/Features/Session/WristHandoffSheet.swift](../../ios/Ond/Features/Session/WristHandoffSheet.swift)               | C      |
| [Ond/Features/Settings/AccountSection.swift](../../ios/Ond/Features/Settings/AccountSection.swift)                   | C      |
| [Ond/Features/Settings/AppleIdentityRequest.swift](../../ios/Ond/Features/Settings/AppleIdentityRequest.swift)       | C      |
| [Ond/Features/Settings/HealthSettingsSection.swift](../../ios/Ond/Features/Settings/HealthSettingsSection.swift)     | C      |
| [Ond/Features/Settings/PracticeSettingsSection.swift](../../ios/Ond/Features/Settings/PracticeSettingsSection.swift) | C      |
| [Ond/Features/Settings/ProfileEditingControls.swift](../../ios/Ond/Features/Settings/ProfileEditingControls.swift)   | C      |
| [Ond/Features/Settings/ProfileView.swift](../../ios/Ond/Features/Settings/ProfileView.swift)                         | C      |
| [Ond/Features/Settings/SettingsControl.swift](../../ios/Ond/Features/Settings/SettingsControl.swift)                 | C      |
| [Ond/Features/Settings/SettingsView.swift](../../ios/Ond/Features/Settings/SettingsView.swift)                       | C      |
| [Ond/Features/Settings/SupportIdentifierRow.swift](../../ios/Ond/Features/Settings/SupportIdentifierRow.swift)       | C      |
| [Ond/Features/Subscription/PaywallPresentation.swift](../../ios/Ond/Features/Subscription/PaywallPresentation.swift) | C      |
| [Ond/Features/Subscription/PaywallView.swift](../../ios/Ond/Features/Subscription/PaywallView.swift)                 | C      |
| [Ond/Features/Subscription/PlusBenefits.swift](../../ios/Ond/Features/Subscription/PlusBenefits.swift)               | C      |
| [Ond/Features/Subscription/SubscriptionPitch.swift](../../ios/Ond/Features/Subscription/SubscriptionPitch.swift)     | C      |
| [Ond/Features/Subscription/SubscriptionTerms.swift](../../ios/Ond/Features/Subscription/SubscriptionTerms.swift)     | C      |
| [Ond/Features/Subscription/UpgradePrompt.swift](../../ios/Ond/Features/Subscription/UpgradePrompt.swift)             | C      |
| [Ond/Features/Techniques/BreathRhythmChart.swift](../../ios/Ond/Features/Techniques/BreathRhythmChart.swift)         | C      |
| [Ond/Features/Techniques/GoalFilterRow.swift](../../ios/Ond/Features/Techniques/GoalFilterRow.swift)                 | C      |
| [Ond/Features/Techniques/RhythmBars.swift](../../ios/Ond/Features/Techniques/RhythmBars.swift)                       | C      |
| [Ond/Features/Techniques/StageTitle.swift](../../ios/Ond/Features/Techniques/StageTitle.swift)                       | C      |
| [Ond/Features/Techniques/TechniqueAboutSection.swift](../../ios/Ond/Features/Techniques/TechniqueAboutSection.swift) | C      |
| [Ond/Features/Techniques/TechniqueCoachDoor.swift](../../ios/Ond/Features/Techniques/TechniqueCoachDoor.swift)       | C      |
| [Ond/Features/Techniques/TechniqueComposerView.swift](../../ios/Ond/Features/Techniques/TechniqueComposerView.swift) | C      |
| [Ond/Features/Techniques/TechniqueDetailView.swift](../../ios/Ond/Features/Techniques/TechniqueDetailView.swift)     | C      |
| [Ond/Features/Techniques/TechniqueDialsView.swift](../../ios/Ond/Features/Techniques/TechniqueDialsView.swift)       | C      |
| [Ond/Features/Techniques/TechniqueListView.swift](../../ios/Ond/Features/Techniques/TechniqueListView.swift)         | C      |
| [Ond/Features/Techniques/TechniquePractice.swift](../../ios/Ond/Features/Techniques/TechniquePractice.swift)         | N      |
| [Ond/Features/Techniques/TechniqueRow.swift](../../ios/Ond/Features/Techniques/TechniqueRow.swift)                   | C      |
| [Ond/Features/Techniques/TechniqueStarButton.swift](../../ios/Ond/Features/Techniques/TechniqueStarButton.swift)     | C      |
| [Ond/FilterPill.swift](../../ios/Ond/FilterPill.swift)                                                               | N      |
| [Ond/FirstRunGate.swift](../../ios/Ond/FirstRunGate.swift)                                                           | N      |
| [Ond/GoalBadge.swift](../../ios/Ond/GoalBadge.swift)                                                                 | N      |
| [Ond/InlineRetry.swift](../../ios/Ond/InlineRetry.swift)                                                             | C      |
| [Ond/LabelledSection.swift](../../ios/Ond/LabelledSection.swift)                                                     | N      |
| [Ond/LegalLinks.swift](../../ios/Ond/LegalLinks.swift)                                                               | C      |
| [Ond/LiveIdentity.swift](../../ios/Ond/LiveIdentity.swift)                                                           | C      |
| [Ond/OndApp.swift](../../ios/Ond/OndApp.swift)                                                                       | C      |
| [Ond/OndAppComposition.swift](../../ios/Ond/OndAppComposition.swift)                                                 | C      |
| [Ond/OndAppLaunchFlags.swift](../../ios/Ond/OndAppLaunchFlags.swift)                                                 | C      |
| [Ond/OndAppScene.swift](../../ios/Ond/OndAppScene.swift)                                                             | N      |
| [Ond/OptionalPickerOptions.swift](../../ios/Ond/OptionalPickerOptions.swift)                                         | C      |
| [Ond/ReadingSection.swift](../../ios/Ond/ReadingSection.swift)                                                       | C      |
| [Ond/Reference.swift](../../ios/Ond/Reference.swift)                                                                 | N      |
| [Ond/ReferenceLoadingView.swift](../../ios/Ond/ReferenceLoadingView.swift)                                           | C      |
| [Ond/ReferenceRetryView.swift](../../ios/Ond/ReferenceRetryView.swift)                                               | C      |
| [Ond/ScreenSubtitle.swift](../../ios/Ond/ScreenSubtitle.swift)                                                       | N      |
| [Ond/ShortcutLink.swift](../../ios/Ond/ShortcutLink.swift)                                                           | N      |
| [Ond/WatchLink.swift](../../ios/Ond/WatchLink.swift)                                                                 | C      |

### OndActivity

| Source                                                                                                       | Status |
| ------------------------------------------------------------------------------------------------------------ | ------ |
| [OndActivity/BreathCue.swift](../../ios/OndActivity/BreathCue.swift)                                         | N      |
| [OndActivity/Intents/SessionControlIntents.swift](../../ios/OndActivity/Intents/SessionControlIntents.swift) | C      |
| [OndActivity/OndActivityBundle.swift](../../ios/OndActivity/OndActivityBundle.swift)                         | C      |
| [OndActivity/PhaseTrack.swift](../../ios/OndActivity/PhaseTrack.swift)                                       | N      |
| [OndActivity/SessionActivityWidget.swift](../../ios/OndActivity/SessionActivityWidget.swift)                 | C      |
| [OndActivity/SessionControls.swift](../../ios/OndActivity/SessionControls.swift)                             | C      |
| [OndActivity/SessionCueLabel.swift](../../ios/OndActivity/SessionCueLabel.swift)                             | C      |
| [OndActivity/SessionLockScreenView.swift](../../ios/OndActivity/SessionLockScreenView.swift)                 | C      |
| [OndActivity/SessionRemainingTime.swift](../../ios/OndActivity/SessionRemainingTime.swift)                   | C      |

### OndWatch

| Source                                                                                                                         | Status |
| ------------------------------------------------------------------------------------------------------------------------------ | ------ |
| [OndWatch/Features/Moments/DiscreetSessionView.swift](../../ios/OndWatch/Features/Moments/DiscreetSessionView.swift)           | C      |
| [OndWatch/Features/Moments/MomentsView.swift](../../ios/OndWatch/Features/Moments/MomentsView.swift)                           | C      |
| [OndWatch/Features/Onboarding/WristConsentView.swift](../../ios/OndWatch/Features/Onboarding/WristConsentView.swift)           | C      |
| [OndWatch/Features/Session/WatchAirOrb.swift](../../ios/OndWatch/Features/Session/WatchAirOrb.swift)                           | N      |
| [OndWatch/Features/Session/ExtendedRuntime.swift](../../ios/OndWatch/Features/Session/ExtendedRuntime.swift)                   | C      |
| [OndWatch/Features/Session/PulseShareView.swift](../../ios/OndWatch/Features/Session/PulseShareView.swift)                     | C      |
| [OndWatch/Features/Session/SessionSummaryView.swift](../../ios/OndWatch/Features/Session/SessionSummaryView.swift)             | C      |
| [OndWatch/Features/Session/SessionView.swift](../../ios/OndWatch/Features/Session/SessionView.swift)                           | C      |
| [OndWatch/Features/Session/WatchHapticController.swift](../../ios/OndWatch/Features/Session/WatchHapticController.swift)       | N      |
| [OndWatch/Features/Session/WatchSessionPlayerView.swift](../../ios/OndWatch/Features/Session/WatchSessionPlayerView.swift)     | C      |
| [OndWatch/Features/Session/WristCuePreviewView.swift](../../ios/OndWatch/Features/Session/WristCuePreviewView.swift)           | C      |
| [OndWatch/Features/Session/WristWarningView.swift](../../ios/OndWatch/Features/Session/WristWarningView.swift)                 | C      |
| [OndWatch/Features/Settings/SettingsView.swift](../../ios/OndWatch/Features/Settings/SettingsView.swift)                       | C      |
| [OndWatch/Features/Techniques/TechniqueCarouselView.swift](../../ios/OndWatch/Features/Techniques/TechniqueCarouselView.swift) | C      |
| [OndWatch/Features/Techniques/TechniqueGlyph.swift](../../ios/OndWatch/Features/Techniques/TechniqueGlyph.swift)               | N      |
| [OndWatch/Features/Techniques/WristStopCard.swift](../../ios/OndWatch/Features/Techniques/WristStopCard.swift)                 | C      |
| [OndWatch/OndWatchApp.swift](../../ios/OndWatch/OndWatchApp.swift)                                                             | C      |
| [OndWatch/PhoneLink.swift](../../ios/OndWatch/PhoneLink.swift)                                                                 | C      |
| [OndWatch/RootMenuView.swift](../../ios/OndWatch/RootMenuView.swift)                                                           | C      |
| [OndWatch/WatchAppDelegate.swift](../../ios/OndWatch/WatchAppDelegate.swift)                                                   | C      |
| [OndWatch/WatchConfiguration.swift](../../ios/OndWatch/WatchConfiguration.swift)                                               | C      |
| [OndWatch/WorkoutRuntime.swift](../../ios/OndWatch/WorkoutRuntime.swift)                                                       | C      |
| [OndWatch/WristLoadingView.swift](../../ios/OndWatch/WristLoadingView.swift)                                                   | C      |

### OndWatchComplication

| Source                                                                                                                   | Status |
| ------------------------------------------------------------------------------------------------------------------------ | ------ |
| [OndWatchComplication/LauncherComplication.swift](../../ios/OndWatchComplication/LauncherComplication.swift)             | C      |
| [OndWatchComplication/OndWatchComplicationBundle.swift](../../ios/OndWatchComplication/OndWatchComplicationBundle.swift) | N      |

### OndKit

| Source                                                                                                                                                  | Status |
| ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| [OndKit/Account/AccountModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/AccountModel.swift)                                               | C      |
| [OndKit/Account/AccountRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/AccountRepository.swift)                                     | C      |
| [OndKit/Account/AccountState.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/AccountState.swift)                                               | C      |
| [OndKit/Account/KeychainIdentityItem.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/KeychainIdentityItem.swift)                               | C      |
| [OndKit/Account/ProvisionedUserIdentityStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/ProvisionedUserIdentityStore.swift)               | C      |
| [OndKit/Account/SessionCredentialCache.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/SessionCredentialCache.swift)                           | C      |
| [OndKit/Account/UserId.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/UserId.swift)                                                           | N      |
| [OndKit/Account/UserIdentityStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/UserIdentityStore.swift)                                     | C      |
| [OndKit/Appearance.swift](../../ios/Packages/OndCore/Sources/OndKit/Appearance.swift)                                                                   | C      |
| [OndKit/Assistant/AssistantConsentStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/AssistantConsentStore.swift)                         | C      |
| [OndKit/Assistant/AssistantRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/AssistantRepository.swift)                             | C      |
| [OndKit/Assistant/Chat.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/Chat.swift)                                                           | C      |
| [OndKit/Assistant/CoachChatModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/CoachChatModel.swift)                                       | C      |
| [OndKit/Assistant/ConsentedAssistant.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/ConsentedAssistant.swift)                               | C      |
| [OndKit/Assistant/ConversationListModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/ConversationListModel.swift)                         | N      |
| [OndKit/Assistant/FileConversationStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/FileConversationStore.swift)                         | C      |
| [OndKit/Assistant/Guidance.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/Guidance.swift)                                                   | C      |
| [OndKit/Assistant/GuidanceModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/GuidanceModel.swift)                                         | C      |
| [OndKit/Assistant/OfferSummary.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/OfferSummary.swift)                                           | C      |
| [OndKit/Assistant/RevealPacer.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/RevealPacer.swift)                                             | C      |
| [OndKit/Collection+Empty.swift](../../ios/Packages/OndCore/Sources/OndKit/Collection+Empty.swift)                                                       | C      |
| [OndKit/Duration+Milliseconds.swift](../../ios/Packages/OndCore/Sources/OndKit/Duration+Milliseconds.swift)                                             | C      |
| [OndKit/Health/CoachHealthContext.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/CoachHealthContext.swift)                                     | N      |
| [OndKit/Health/HealthContextModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/HealthContextModel.swift)                                     | C      |
| [OndKit/Health/HealthKitHealthStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/HealthKitHealthStore.swift)                                 | C      |
| [OndKit/Health/HealthKitReadBoundary.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/HealthKitReadBoundary.swift)                               | C      |
| [OndKit/Health/HealthStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/HealthStore.swift)                                                   | C      |
| [OndKit/Health/HealthSummaryBuilder.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/HealthSummaryBuilder.swift)                                 | C      |
| [OndKit/Health/HealthTrendsState.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/HealthTrendsState.swift)                                       | C      |
| [OndKit/Health/MindfulMinutesRecorder.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/MindfulMinutesRecorder.swift)                             | C      |
| [OndKit/Health/Mood.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/Mood.swift)                                                                 | C      |
| [OndKit/Health/MoodCheckModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/MoodCheckModel.swift)                                             | C      |
| [OndKit/Health/MoodRecorder.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/MoodRecorder.swift)                                                 | N      |
| [OndKit/Home/DialStop+Bands.swift](../../ios/Packages/OndCore/Sources/OndKit/Home/DialStop+Bands.swift)                                                 | N      |
| [OndKit/Home/DialStop.swift](../../ios/Packages/OndCore/Sources/OndKit/Home/DialStop.swift)                                                             | C      |
| [OndKit/Home/HomeChoiceStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Home/HomeChoiceStore.swift)                                               | C      |
| [OndKit/Home/HomeOffer.swift](../../ios/Packages/OndCore/Sources/OndKit/Home/HomeOffer.swift)                                                           | C      |
| [OndKit/Home/HomeStateLine.swift](../../ios/Packages/OndCore/Sources/OndKit/Home/HomeStateLine.swift)                                                   | C      |
| [OndKit/Home/HomeSuggestion.swift](../../ios/Packages/OndCore/Sources/OndKit/Home/HomeSuggestion.swift)                                                 | C      |
| [OndKit/Home/StarredStopStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Home/StarredStopStore.swift)                                             | C      |
| [OndKit/Journey/BoltScore.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/BoltScore.swift)                                                     | C      |
| [OndKit/Journey/JourneyModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/JourneyModel.swift)                                               | C      |
| [OndKit/Journey/JourneyRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/JourneyRepository.swift)                                     | C      |
| [OndKit/Journey/JourneyStats.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/JourneyStats.swift)                                               | N      |
| [OndKit/Journey/Leaderboard.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/Leaderboard.swift)                                                 | C      |
| [OndKit/Journey/LeaderboardLines.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/LeaderboardLines.swift)                                       | C      |
| [OndKit/Journey/LeaderboardNameGenerator.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/LeaderboardNameGenerator.swift)                       | C      |
| [OndKit/Journey/PracticeHeartline.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/PracticeHeartline.swift)                                     | C      |
| [OndKit/Journey/PracticeRhythm.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/PracticeRhythm.swift)                                           | C      |
| [OndKit/Journey/PracticeStage.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/PracticeStage.swift)                                             | C      |
| [OndKit/Journey/RestingRate.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/RestingRate.swift)                                                 | C      |
| [OndKit/Journey/SessionDay.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/SessionDay.swift)                                                   | C      |
| [OndKit/Log.swift](../../ios/Packages/OndCore/Sources/OndKit/Log.swift)                                                                                 | C      |
| [OndKit/Notifications/NotificationDestination.swift](../../ios/Packages/OndCore/Sources/OndKit/Notifications/NotificationDestination.swift)             | N      |
| [OndKit/Notifications/NotificationPayload.swift](../../ios/Packages/OndCore/Sources/OndKit/Notifications/NotificationPayload.swift)                     | C      |
| [OndKit/Notifications/NotificationRouter.swift](../../ios/Packages/OndCore/Sources/OndKit/Notifications/NotificationRouter.swift)                       | N      |
| [OndKit/Notifications/ReminderDial.swift](../../ios/Packages/OndCore/Sources/OndKit/Notifications/ReminderDial.swift)                                   | C      |
| [OndKit/Notifications/ReminderSeed.swift](../../ios/Packages/OndCore/Sources/OndKit/Notifications/ReminderSeed.swift)                                   | C      |
| [OndKit/Notifications/Schedule.swift](../../ios/Packages/OndCore/Sources/OndKit/Notifications/Schedule.swift)                                           | C      |
| [OndKit/Notifications/ScheduleStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Notifications/ScheduleStore.swift)                                 | C      |
| [OndKit/Profile/OnboardingModel+OptIns.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/OnboardingModel+OptIns.swift)                           | N      |
| [OndKit/Profile/OnboardingModel+Step.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/OnboardingModel+Step.swift)                               | C      |
| [OndKit/Profile/OnboardingModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/OnboardingModel.swift)                                         | C      |
| [OndKit/Profile/Profile.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/Profile.swift)                                                         | C      |
| [OndKit/Profile/ProfileEditModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/ProfileEditModel.swift)                                       | C      |
| [OndKit/Profile/ProfileRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/ProfileRepository.swift)                                     | C      |
| [OndKit/Profile/ProfileStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/ProfileStore.swift)                                               | C      |
| [OndKit/Profile/SafetyConsent.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/SafetyConsent.swift)                                             | C      |
| [OndKit/Profile/SafetyConsentStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/SafetyConsentStore.swift)                                   | C      |
| [OndKit/Reference/CachedReferenceRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/CachedReferenceRepository.swift)                 | C      |
| [OndKit/Reference/CatalogueExport.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/CatalogueExport.swift)                                     | C      |
| [OndKit/Reference/CatalogueExportVocabulary.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/CatalogueExportVocabulary.swift)                 | C      |
| [OndKit/Reference/FoundationTopic.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/FoundationTopic.swift)                                     | N      |
| [OndKit/Reference/FoundationsModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/FoundationsModel.swift)                                   | C      |
| [OndKit/Reference/OccasionCatalogue+Decoding.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/OccasionCatalogue+Decoding.swift)               | C      |
| [OndKit/Reference/OccasionCatalogue.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/OccasionCatalogue.swift)                                 | C      |
| [OndKit/Reference/OccasionCatalogueModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/OccasionCatalogueModel.swift)                       | C      |
| [OndKit/Reference/ReadingContent.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/ReadingContent.swift)                                       | C      |
| [OndKit/Reference/ReferenceFreshness.swift](../../ios/Packages/OndCore/Sources/OndKit/Reference/ReferenceFreshness.swift)                               | C      |
| [OndKit/Session/CuePreview.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/CuePreview.swift)                                                   | N      |
| [OndKit/Session/DiscreetCadence.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/DiscreetCadence.swift)                                         | N      |
| [OndKit/Session/DiscreetSessionModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/DiscreetSessionModel.swift)                               | C      |
| [OndKit/Session/FileSessionStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/FileSessionStore.swift)                                       | C      |
| [OndKit/Session/HapticPattern.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/HapticPattern.swift)                                             | C      |
| [OndKit/Session/HapticStrength.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/HapticStrength.swift)                                           | C      |
| [OndKit/Session/SessionActivity.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionActivity.swift)                                         | C      |
| [OndKit/Session/SessionActivityAttributes.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionActivityAttributes.swift)                     | N      |
| [OndKit/Session/SessionActivityUpdatePolicy.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionActivityUpdatePolicy.swift)                 | N      |
| [OndKit/Session/SessionClock.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionClock.swift)                                               | N      |
| [OndKit/Session/SessionCueMode.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionCueMode.swift)                                           | C      |
| [OndKit/Session/SessionCueing.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionCueing.swift)                                             | N      |
| [OndKit/Session/SessionGuidance.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionGuidance.swift)                                         | C      |
| [OndKit/Session/SessionHapticShape.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionHapticShape.swift)                                   | N      |
| [OndKit/Session/SessionLaunchResolver.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionLaunchResolver.swift)                             | N      |
| [OndKit/Session/SessionModel+Outcome.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionModel+Outcome.swift)                               | N      |
| [OndKit/Session/SessionModel+Progress.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionModel+Progress.swift)                             | C      |
| [OndKit/Session/SessionModel+Starting.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionModel+Starting.swift)                             | N      |
| [OndKit/Session/SessionModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionModel.swift)                                               | C      |
| [OndKit/Session/SessionPausedNotice.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionPausedNotice.swift)                                 | C      |
| [OndKit/Session/SessionPresence.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionPresence.swift)                                         | C      |
| [OndKit/Session/SessionRecord+Wire.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionRecord+Wire.swift)                                   | C      |
| [OndKit/Session/SessionRecord.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionRecord.swift)                                             | N      |
| [OndKit/Session/SessionSettings.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionSettings.swift)                                         | C      |
| [OndKit/Session/SessionSummaryLines.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionSummaryLines.swift)                                 | C      |
| [OndKit/Session/SessionSyncQueue+Restore.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionSyncQueue+Restore.swift)                       | C      |
| [OndKit/Session/SessionSyncQueue.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionSyncQueue.swift)                                       | C      |
| [OndKit/Session/SessionTimeline+Layout.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionTimeline+Layout.swift)                           | N      |
| [OndKit/Session/SessionTimeline.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionTimeline.swift)                                         | C      |
| [OndKit/Session/SessionTurnGap.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionTurnGap.swift)                                           | N      |
| [OndKit/Session/SyncLedger.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SyncLedger.swift)                                                   | N      |
| [OndKit/Session/TechniqueWarningStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/TechniqueWarningStore.swift)                             | C      |
| [OndKit/Session/TombstoneStoring.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/TombstoneStoring.swift)                                       | N      |
| [OndKit/Session/ToneSynthesizer.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/ToneSynthesizer.swift)                                         | C      |
| [OndKit/Storage/DefaultsJSONStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Storage/DefaultsJSONStore.swift)                                     | C      |
| [OndKit/Storage/JSONFileStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Storage/JSONFileStore.swift)                                             | C      |
| [OndKit/Storage/KeychainItem.swift](../../ios/Packages/OndCore/Sources/OndKit/Storage/KeychainItem.swift)                                               | C      |
| [OndKit/Storage/PersonalStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Storage/PersonalStore.swift)                                             | N      |
| [OndKit/Storage/UserDefaults+Flag.swift](../../ios/Packages/OndCore/Sources/OndKit/Storage/UserDefaults+Flag.swift)                                     | N      |
| [OndKit/Subscription/EntitlementRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/EntitlementRepository.swift)                   | C      |
| [OndKit/Subscription/StoreFront.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/StoreFront.swift)                                         | C      |
| [OndKit/Subscription/StoreKitStoreFront.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/StoreKitStoreFront.swift)                         | C      |
| [OndKit/Subscription/SubscriptionRefreshCoordinator.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/SubscriptionRefreshCoordinator.swift) | N      |
| [OndKit/Subscription/SubscriptionStore+Offer.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/SubscriptionStore+Offer.swift)               | C      |
| [OndKit/Subscription/SubscriptionStore+Renewal.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/SubscriptionStore+Renewal.swift)           | N      |
| [OndKit/Subscription/SubscriptionStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/SubscriptionStore.swift)                           | C      |
| [OndKit/Subscription/SubscriptionTier.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/SubscriptionTier.swift)                             | C      |
| [OndKit/Technique/Breath.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/Breath.swift)                                                       | N      |
| [OndKit/Technique/BreathCueRole.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/BreathCueRole.swift)                                         | C      |
| [OndKit/Technique/BreathHint.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/BreathHint.swift)                                               | C      |
| [OndKit/Technique/BreathRhythm.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/BreathRhythm.swift)                                           | N      |
| [OndKit/Technique/BreathSteps.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/BreathSteps.swift)                                             | C      |
| [OndKit/Technique/BreathVisualStyle.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/BreathVisualStyle.swift)                                 | C      |
| [OndKit/Technique/CachedUserTechniqueRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/CachedUserTechniqueRepository.swift)         | C      |
| [OndKit/Technique/Manner.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/Manner.swift)                                                       | C      |
| [OndKit/Technique/MomentsBoard.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/MomentsBoard.swift)                                           | N      |
| [OndKit/Technique/Passage.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/Passage.swift)                                                     | C      |
| [OndKit/Technique/Physiology.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/Physiology.swift)                                               | N      |
| [OndKit/Technique/ProportionalShares.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/ProportionalShares.swift)                               | N      |
| [OndKit/Technique/Technique.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/Technique.swift)                                                 | C      |
| [OndKit/Technique/TechniqueDraft.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueDraft.swift)                                       | C      |
| [OndKit/Technique/TechniqueFigure.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueFigure.swift)                                     | C      |
| [OndKit/Technique/TechniqueFigureDrawing.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueFigureDrawing.swift)                       | C      |
| [OndKit/Technique/TechniqueGoal+Present.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueGoal+Present.swift)                         | N      |
| [OndKit/Technique/TechniqueIdentifiers.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueIdentifiers.swift)                           | N      |
| [OndKit/Technique/TechniqueListModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueListModel.swift)                               | C      |
| [OndKit/Technique/TechniqueOverrides.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueOverrides.swift)                               | C      |
| [OndKit/Technique/TechniqueRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueRepository.swift)                             | C      |
| [OndKit/Technique/TechniqueVocabulary.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueVocabulary.swift)                             | C      |
| [OndKit/Technique/TechniqueWireVocabulary.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueWireVocabulary.swift)                     | C      |
| [OndKit/Technique/TechniqueWords.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueWords.swift)                                       | C      |
| [OndKit/Technique/UserTechniqueModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/UserTechniqueModel.swift)                               | C      |
| [OndKit/Technique/UserTechniqueRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/UserTechniqueRepository.swift)                     | C      |
| [OndKit/Transport/Deployment.swift](../../ios/Packages/OndCore/Sources/OndKit/Transport/Deployment.swift)                                               | C      |
| [OndKit/Transport/ResponseMessage.swift](../../ios/Packages/OndCore/Sources/OndKit/Transport/ResponseMessage.swift)                                     | C      |
| [OndKit/Transport/TransportFault.swift](../../ios/Packages/OndCore/Sources/OndKit/Transport/TransportFault.swift)                                       | C      |
| [OndKit/Watch/OrderedMoment.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/OrderedMoment.swift)                                                 | N      |
| [OndKit/Watch/PulseMonitor+Rehearsal.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/PulseMonitor+Rehearsal.swift)                               | N      |
| [OndKit/Watch/PulseMonitor.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/PulseMonitor.swift)                                                   | C      |
| [OndKit/Watch/PulseRelay.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/PulseRelay.swift)                                                       | C      |
| [OndKit/Watch/PulseSource.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/PulseSource.swift)                                                     | N      |
| [OndKit/Watch/PulseTrace.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/PulseTrace.swift)                                                       | N      |
| [OndKit/Watch/WatchCue.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchCue.swift)                                                           | N      |
| [OndKit/Watch/WatchHandoff.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchHandoff.swift)                                                   | C      |
| [OndKit/Watch/WatchHandoffInbox.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchHandoffInbox.swift)                                         | C      |
| [OndKit/Watch/WatchHandoffOutbox.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchHandoffOutbox.swift)                                       | C      |
| [OndKit/Watch/WatchHapticStyle.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchHapticStyle.swift)                                           | C      |
| [OndKit/Watch/WatchOrderLedger.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchOrderLedger.swift)                                           | C      |
| [OndKit/Watch/WatchPulse.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchPulse.swift)                                                       | C      |
| [OndKit/Watch/WatchSessionOrder.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchSessionOrder.swift)                                         | C      |
| [OndKit/Watch/WatchSettings.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchSettings.swift)                                                 | C      |
| [OndKit/Watch/WristCatalogue.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WristCatalogue.swift)                                               | N      |
| [OndKit/Watch/WristLaunchModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WristLaunchModel.swift)                                           | C      |
| [OndKit/Watch/WristLauncher.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WristLauncher.swift)                                                 | C      |
| [OndKit/Watch/WristLaunching.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WristLaunching.swift)                                               | N      |
| [OndKit/Watch/WristOrderModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WristOrderModel.swift)                                             | C      |
| [OndKit/Watch/WristShelf.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/WristShelf.swift)                                                       | N      |

### OndStyle

| Source                                                                                                    | Status |
| --------------------------------------------------------------------------------------------------------- | ------ |
| [OndStyle/BreathFigure.swift](../../ios/Packages/OndCore/Sources/OndStyle/BreathFigure.swift)             | N      |
| [OndStyle/BreathFigurePose.swift](../../ios/Packages/OndCore/Sources/OndStyle/BreathFigurePose.swift)     | N      |
| [OndStyle/BreathFigureShape.swift](../../ios/Packages/OndCore/Sources/OndStyle/BreathFigureShape.swift)   | N      |
| [OndStyle/BreathFigureView.swift](../../ios/Packages/OndCore/Sources/OndStyle/BreathFigureView.swift)     | N      |
| [OndStyle/BreathGlyphPose.swift](../../ios/Packages/OndCore/Sources/OndStyle/BreathGlyphPose.swift)       | C      |
| [OndStyle/FigureShape.swift](../../ios/Packages/OndCore/Sources/OndStyle/FigureShape.swift)               | N      |
| [OndStyle/FigureStrokes.swift](../../ios/Packages/OndCore/Sources/OndStyle/FigureStrokes.swift)           | N      |
| [OndStyle/GoalAccent.swift](../../ios/Packages/OndCore/Sources/OndStyle/GoalAccent.swift)                 | N      |
| [OndStyle/PlayfulShapes.swift](../../ios/Packages/OndCore/Sources/OndStyle/PlayfulShapes.swift)           | N      |
| [OndStyle/SessionPresenceCue.swift](../../ios/Packages/OndCore/Sources/OndStyle/SessionPresenceCue.swift) | C      |

### OndUI

| Source                                                                                                | Status |
| ----------------------------------------------------------------------------------------------------- | ------ |
| [OndUI/AmbientBreath.swift](../../ios/Packages/OndCore/Sources/OndUI/AmbientBreath.swift)             | N      |
| [OndUI/BreathGlyph.swift](../../ios/Packages/OndCore/Sources/OndUI/BreathGlyph.swift)                 | N      |
| [OndUI/CautionRule.swift](../../ios/Packages/OndCore/Sources/OndUI/CautionRule.swift)                 | N      |
| [OndUI/ColorToken.swift](../../ios/Packages/OndCore/Sources/OndUI/ColorToken.swift)                   | C      |
| [OndUI/DoorCard.swift](../../ios/Packages/OndCore/Sources/OndUI/DoorCard.swift)                       | C      |
| [OndUI/OpenRingGeometry.swift](../../ios/Packages/OndCore/Sources/OndUI/OpenRingGeometry.swift)       | N      |
| [OndUI/OpenRingMark.swift](../../ios/Packages/OndCore/Sources/OndUI/OpenRingMark.swift)               | N      |
| [OndUI/PhaseArc.swift](../../ios/Packages/OndCore/Sources/OndUI/PhaseArc.swift)                       | N      |
| [OndUI/PrimaryAction.swift](../../ios/Packages/OndCore/Sources/OndUI/PrimaryAction.swift)             | N      |
| [OndUI/RevealingText.swift](../../ios/Packages/OndCore/Sources/OndUI/RevealingText.swift)             | N      |
| [OndUI/SessionArc.swift](../../ios/Packages/OndCore/Sources/OndUI/SessionArc.swift)                   | N      |
| [OndUI/Theme.swift](../../ios/Packages/OndCore/Sources/OndUI/Theme.swift)                             | C      |
| [OndUI/Typeface.swift](../../ios/Packages/OndCore/Sources/OndUI/Typeface.swift)                       | C      |
| [OndUI/View+AccentGround.swift](../../ios/Packages/OndCore/Sources/OndUI/View+AccentGround.swift)     | N      |
| [OndUI/View+DisplayNumeral.swift](../../ios/Packages/OndCore/Sources/OndUI/View+DisplayNumeral.swift) | N      |
| [OndUI/View+Eyebrow.swift](../../ios/Packages/OndCore/Sources/OndUI/View+Eyebrow.swift)               | N      |
| [OndUI/View+FigureGround.swift](../../ios/Packages/OndCore/Sources/OndUI/View+FigureGround.swift)     | N      |
| [OndUI/View+Glass.swift](../../ios/Packages/OndCore/Sources/OndUI/View+Glass.swift)                   | N      |
| [OndUI/View+PaletteGround.swift](../../ios/Packages/OndCore/Sources/OndUI/View+PaletteGround.swift)   | N      |
| [OndUI/View+Plate.swift](../../ios/Packages/OndCore/Sources/OndUI/View+Plate.swift)                   | N      |
| [OndUI/View+TapTarget.swift](../../ios/Packages/OndCore/Sources/OndUI/View+TapTarget.swift)           | N      |
| [OndUI/View+WristGround.swift](../../ios/Packages/OndCore/Sources/OndUI/View+WristGround.swift)       | N      |
| [OndUI/Wordmark.swift](../../ios/Packages/OndCore/Sources/OndUI/Wordmark.swift)                       | C      |

## Catalogue records

Authoritative wording: [catalogue.rs](../../crates/migrate/src/seed/catalogue.rs). Companion shipped data: [catalogue.json](../../ios/Packages/OndCore/Sources/OndKit/Resources/catalogue.json). Reviewed names, summaries, preparation, safety, mechanism and evidence for each exercise; question/answer copy for each Basics topic; title, summary and caution for each Moment; and introductory-step wording. Timings and surface/register fields were inspected where they constrain the words. Record counts were checked against the bundle; this audit did not rerun generation or query a deployed database.

### Exercises (13)

- `box-breathing` — Box Breathing
- `coherent-breathing` — Coherent Breathing
- `four-seven-eight` — 4-7-8 Breathing
- `extended-exhale` — Extended Exhale
- `physiological-sigh` — Physiological Sigh
- `cyclic-sighing` — Cyclic Sighing
- `pursed-lip-breathing` — Pursed-Lip Breathing
- `humming-breath` — Humming Breath
- `cooling-breath` — Cooling Breath
- `bellows-breath` — Bellows Breath
- `wim-hof-rounds` — Wim Hof-style Rounds
- `long-box-breathing` — Long Box Breathing
- `alternate-nostril` — Alternate-Nostril Breathing

### Basics (13)

- `what-matters-most` — How exact does it need to be?
- `what-a-good-breath-feels-like` — What should a good breath feel like?
- `is-a-deep-breath-the-answer` — Is a deep breath always the answer?
- `why-it-works` — Why can slow breathing help?
- `belly-or-chest` — Belly or chest?
- `nose-or-mouth` — Nose or mouth?
- `how-slow` — How slow?
- `fast-breathing-and-holds` — What about fast breathing and holds?
- `getting-comfortable` — How should I get comfortable?
- `how-long` — How long and how often?
- `when-breathing-is-the-problem` — When breathing itself is the problem
- `how-good-is-the-evidence` — How good is the evidence?
- `why-no-scores` — What do breathing numbers mean?

### Moments (17)

- `five-minutes-today` — Five minutes today
- `ten-quiet-minutes` — Ten quiet minutes
- `before-a-presentation` — Before a presentation
- `after-a-hard-meeting` — After a hard meeting
- `through-this-meeting` — Through this meeting
- `after-a-workout` — After a workout
- `when-youre-winded` — When you're winded
- `when-you-cant-get-a-satisfying-breath` — When you can't get a satisfying breath
- `when-panic-is-rising` — When panic is rising
- `in-a-tight-spot` — In a tight spot
- `overloaded-and-need-quiet` — Overloaded and need quiet
- `feeling-queasy` — Feeling queasy
- `winding-down` — Winding down
- `awake-at-3am` — Awake at 3am
- `with-your-child` — With your child
- `a-moment-to-reset` — A moment to reset
- `riding-out-a-craving` — Riding out a craving

### Introductory steps (5)

- `box-breathing`
- `physiological-sigh`
- `cyclic-sighing`
- `extended-exhale`
- `coherent-breathing`

## Other authored surfaces and contracts

| Source | Coverage |
| --- | --- |
| [ios/project.yml](../../ios/project.yml) | App/display names; iPhone and Watch Health and local-network purpose descriptions. |
| [ios/Ond/Ond.storekit](../../ios/Ond/Ond.storekit) | Local subscription display names, descriptions, prices and introductory-offer fixtures. These do not establish App Store Connect values. |
| [ios/Packages/OndCore/Sources/OndAPI/TransportOutcome.swift](../../ios/Packages/OndCore/Sources/OndAPI/TransportOutcome.swift) | Transport-code classification: confirms which failures become native recovery language. |
| [ios/Packages/OndCore/Sources/OndAPI/Clients.swift](../../ios/Packages/OndCore/Sources/OndAPI/Clients.swift) | Transport surface screened; no independent authored product prose. |
| [ios/Packages/OndCore/Sources/OndAPI/IdentityInterceptor.swift](../../ios/Packages/OndCore/Sources/OndAPI/IdentityInterceptor.swift) | Identity transport surface screened; technical failures are not assumed to be direct UI copy. |
| [crates/api/src/features/assistant/fallback.rs](../../crates/api/src/features/assistant/fallback.rs) | Fixed recommendation and unavailable-chat wording; test fixtures excluded. |
| [crates/api/src/features/assistant/prompt/copy/prefix.md](../../crates/api/src/features/assistant/prompt/copy/prefix.md) | Complete authored coach brief: voice, evidence, symptoms, measurement interpretation, offer etiquette and refusals. |
| [crates/api/src/features/assistant/prompt/prefix.rs](../../crates/api/src/features/assistant/prompt/prefix.rs) | Catalogue, Moment, Foundations index and measurement-band prompt construction. |
| [crates/api/src/features/assistant/prompt/instructions.rs](../../crates/api/src/features/assistant/prompt/instructions.rs) | Per-user context and output instructions, including first name, saved names, Health and practice summaries. |
| [crates/api/src/features/assistant/types.rs](../../crates/api/src/features/assistant/types.rs) | Goal/demographic phrasing and context boundaries; numeric contracts distinguished from copy. |
| [crates/api/src/features/assistant/stream.rs](../../crates/api/src/features/assistant/stream.rs) | Fixed validation/interruption phrases and history/offer context boundary. |
| [crates/api/src/features/assistant/tools/exercise.rs](../../crates/api/src/features/assistant/tools/exercise.rs) | Authored tool description and parameter explanations for exercise offers. |
| [crates/api/src/features/assistant/tools/saved_exercise.rs](../../crates/api/src/features/assistant/tools/saved_exercise.rs) | Authored tool description, proposed names/summaries and parameter explanations. |
| [crates/api/src/features/assistant/tools/bolt.rs](../../crates/api/src/features/assistant/tools/bolt.rs) | BOLT offer description and diagnostic boundary. |
| [crates/api/src/features/assistant/tools/dispatch.rs](../../crates/api/src/features/assistant/tools/dispatch.rs) | Offer resolution boundary; no additional product copy. |
| [crates/api/src/features/user_technique/validation.rs](../../crates/api/src/features/user_technique/validation.rs) | All runtime validation messages, including limits and fast-breathing/hold rejection; direct native exposure checked. |
| [crates/api/src/features/profile/service.rs](../../crates/api/src/features/profile/service.rs) | Runtime profile validation phrases; direct native rejection exposure checked. |
| [crates/api/src/features/profile/errors.rs](../../crates/api/src/features/profile/errors.rs) | Display-name conflict and server error mapping. |
| [crates/api/src/features/user_technique/errors.rs](../../crates/api/src/features/user_technique/errors.rs) | Authoring refusal and error mapping. |
| [crates/api/src/features/account/errors.rs](../../crates/api/src/features/account/errors.rs) | Credential errors classified against the native replacement messages. |
| [crates/api/src/features/entitlement/errors.rs](../../crates/api/src/features/entitlement/errors.rs) | Entitlement refusal/error boundary against native presentation. |
| [crates/api/src/features/journey/errors.rs](../../crates/api/src/features/journey/errors.rs) | Journey refusal/error mapping; diagnostic text distinguished from displayed recovery. |
| [crates/api/src/features/journey/sessions/validation.rs](../../crates/api/src/features/journey/sessions/validation.rs) | Timestamp-validation wording and error boundary. |
| [crates/api/src/features/technique/errors.rs](../../crates/api/src/features/technique/errors.rs) | Catalogue error mapping. |
| [crates/api/src/features/assistant/errors.rs](../../crates/api/src/features/assistant/errors.rs) | Assistant error mapping. |
| [web/index.html](../../web/index.html) | All authored homepage copy, metadata, links, image descriptions and feature/pricing explanations. |
| [web/privacy.html](../../web/privacy.html) | All authored policy copy, metadata and rights/consent/retention explanations; product facts traced where disputed. Not a legal certification. |
| [web/support.html](../../web/support.html) | All authored support, recovery, contact, metadata and FAQ copy. |
| [docs/product/listing.md](../../docs/product/listing.md) | Local listing and screenshot-copy guidance; not live App Store metadata. |
| [docs/product/naming.md](../../docs/product/naming.md) | Brand naming and product-name consistency. |
| [docs/product/breathing-foundations.md](../../docs/product/breathing-foundations.md) | Claim-boundary cross-check for all Basics topics. |
| [docs/product/breathing-science.md](../../docs/product/breathing-science.md) | Existing substantiation and scope boundaries for catalogue claims; not a fresh verification of every external paper. |

## Coverage that requires a different kind of evidence

The source review covers the authored wording within this boundary. The following remain unverified: every possible AI reply or user-authored text; the running provider's behaviour and retention configuration; production database/catalogue and published website content; real subscription names/prices/trial eligibility and App Store privacy answers; system-owned permission/payment dialogues; translated languages and regional number/date pronunciation; rendered truncation and VoiceOver order for every dynamic state; clinical adequacy and every study's current evidence status. These are explicit release checks, not additional unreviewed native string files.
