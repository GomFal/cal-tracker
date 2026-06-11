import 'dart:async';
import 'dart:io';

import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNutritionRepository extends Mock implements NutritionRepository {}

class MockAudioRecorderService extends Mock implements AudioRecorderService {}

class FakeFile extends Fake implements File {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeFile());
  });

  group('VoiceLogViewModel', () {
    late MockNutritionRepository mockNutritionRepository;
    late MockAudioRecorderService mockAudioRecorderService;
    late VoiceLogViewModel viewModel;

    setUp(() {
      mockNutritionRepository = MockNutritionRepository();
      mockAudioRecorderService = MockAudioRecorderService();
      when(() => mockAudioRecorderService.dispose()).thenAnswer((_) async {});
      when(
        () => mockAudioRecorderService.stateStream,
      ).thenAnswer((_) => const Stream.empty());
      viewModel = VoiceLogViewModel(
        nutritionRepository: mockNutritionRepository,
        audioRecorderService: mockAudioRecorderService,
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    void recreateViewModel({DateTime Function()? now}) {
      viewModel.dispose();
      viewModel = VoiceLogViewModel(
        nutritionRepository: mockNutritionRepository,
        audioRecorderService: mockAudioRecorderService,
        now: now,
      );
    }

    test('initial state is idle', () {
      expect(viewModel.state, VoiceLogState.idle);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.errorMessage, isNull);
    });

    test('searchFoods delegates to repository', () async {
      final bread = _mealItem(name: 'Bread', calories: 265);
      when(
        () => mockNutritionRepository.searchFoods('bread', limit: 10),
      ).thenAnswer((_) async => FoodSearchResult(items: [bread]));

      final result = await viewModel.searchFoods('bread');

      expect(result.items.single.name, 'Bread');
      verify(
        () => mockNutritionRepository.searchFoods('bread', limit: 10),
      ).called(1);
    });

    test('creates proposal from manually selected foods', () async {
      final bread = _mealItem(name: 'Bread', calories: 265);
      const proposal = MealProposal(
        id: 'manual_prop',
        title: 'Bread',
        confidence: 0.9,
        requiresConfirmation: true,
        trustedAutoCommitEligible: false,
        nutrition: NutritionSnapshot(
          calories: 265,
          proteinGrams: 7,
          carbsGrams: 1,
          fatGrams: 8,
        ),
        items: [],
      );
      when(
        () => mockNutritionRepository.createProposalFromItems(
          phrase: any(named: 'phrase'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async => proposal);

      await viewModel.createProposalFromManualItems([bread]);

      expect(viewModel.state, VoiceLogState.proposalReady);
      expect(viewModel.proposal, proposal);
      final captured = verify(
        () => mockNutritionRepository.createProposalFromItems(
          phrase: any(named: 'phrase'),
          items: captureAny(named: 'items'),
        ),
      ).captured.single as List<MealItem>;
      expect(captured.single.name, 'Bread');
    });

    group('toggleRecording', () {
      testWidgets('tracks recording duration from elapsed wall time',
          (tester) async {
        recreateViewModel(now: tester.binding.clock.now);
        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});

        await viewModel.startRecording();

        expect(viewModel.state, VoiceLogState.recording);
        expect(viewModel.recordingDuration, Duration.zero);

        await tester.pump(const Duration(seconds: 1));
        expect(viewModel.recordingDuration, const Duration(seconds: 1));

        await tester.pump(const Duration(seconds: 2));
        expect(viewModel.recordingDuration, const Duration(seconds: 3));

        viewModel.clearResult();
      });

      testWidgets(
          'ignores duplicate start requests while starting or recording',
          (tester) async {
        recreateViewModel(now: tester.binding.clock.now);
        final startCompleter = Completer<void>();
        when(
          () => mockAudioRecorderService.start(),
        ).thenAnswer((_) => startCompleter.future);

        unawaited(viewModel.startRecording());
        expect(viewModel.state, VoiceLogState.requestingPermission);

        unawaited(viewModel.startRecording());
        await tester.pump();
        expect(viewModel.state, VoiceLogState.requestingPermission);

        startCompleter.complete();
        await tester.pump();
        expect(viewModel.state, VoiceLogState.recording);

        unawaited(viewModel.startRecording());
        await tester.pump();

        await tester.pump(const Duration(seconds: 2));
        expect(viewModel.recordingDuration, const Duration(seconds: 2));

        viewModel.clearResult();

        verify(() => mockAudioRecorderService.start()).called(1);
      });

      testWidgets(
          'clearResult cancels active recording timer before next recording',
          (tester) async {
        recreateViewModel(now: tester.binding.clock.now);
        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});

        await viewModel.startRecording();
        expect(viewModel.state, VoiceLogState.recording);

        await tester.pump(const Duration(seconds: 2));
        expect(viewModel.recordingDuration, const Duration(seconds: 2));

        viewModel.clearResult();
        expect(viewModel.state, VoiceLogState.idle);
        expect(viewModel.recordingDuration, Duration.zero);

        await tester.pump(const Duration(seconds: 5));
        expect(viewModel.recordingDuration, Duration.zero);

        await viewModel.startRecording();
        expect(viewModel.state, VoiceLogState.recording);
        expect(viewModel.recordingDuration, Duration.zero);

        await tester.pump(const Duration(seconds: 1));
        expect(viewModel.recordingDuration, const Duration(seconds: 1));

        viewModel.clearResult();

        verify(() => mockAudioRecorderService.start()).called(2);
      });

      test('starts recording when idle', () async {
        when(
          () => mockAudioRecorderService.hasPermission(),
        ).thenAnswer((_) async => true);
        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});

        final states = <VoiceLogState>[];
        viewModel.addListener(() => states.add(viewModel.state));

        await viewModel.toggleRecording();

        expect(viewModel.state, VoiceLogState.recording);
        verify(() => mockAudioRecorderService.start()).called(1);
      });

      test('stops recording and transitions to transcriptReady', () async {
        when(
          () => mockAudioRecorderService.hasPermission(),
        ).thenAnswer((_) async => true);
        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
        when(() => mockAudioRecorderService.stop()).thenAnswer(
          (_) async => const RecordedAudio(
            path: '/tmp/test.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 1024,
          ),
        );
        when(
          () => mockNutritionRepository.transcribeAudio(any()),
        ).thenAnswer((_) async => 'chicken and rice');

        await viewModel.toggleRecording(); // start
        expect(viewModel.state, VoiceLogState.recording);

        // Trigger stop
        await viewModel.toggleRecording();

        // Wait for transcribing -> transcriptReady transition
        await Future.delayed(const Duration(milliseconds: 100));

        expect(viewModel.state, VoiceLogState.transcriptReady);
        expect(viewModel.transcript, 'chicken and rice');
        expect(viewModel.hasVoiceTranscript, isTrue);
      });

      test('stops global recording and creates proposal from audio', () async {
        const proposal = MealProposal(
          id: 'voice_prop_1',
          title: 'Chicken and rice',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 500,
            proteinGrams: 30,
            carbsGrams: 60,
            fatGrams: 15,
          ),
          items: [],
        );
        when(
          () => mockAudioRecorderService.hasPermission(),
        ).thenAnswer((_) async => true);
        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
        when(() => mockAudioRecorderService.stop()).thenAnswer(
          (_) async => const RecordedAudio(
            path: '/tmp/test.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 1024,
          ),
        );
        when(() => mockNutritionRepository.logAudio(any())).thenAnswer(
          (_) async => const VoiceMealRunResult(
            transcript: 'chicken and rice',
            provider: 'test',
            model: 'test-model',
            traceId: 'trace-1',
            result: AgentRunResult(
              kind: 'proposal',
              proposal: proposal,
              message: 'Meal proposal created.',
            ),
          ),
        );

        await viewModel.toggleGlobalRecording();
        expect(viewModel.state, VoiceLogState.recording);

        await viewModel.toggleGlobalRecording();
        await Future.delayed(const Duration(milliseconds: 100));

        expect(viewModel.state, VoiceLogState.proposalReady);
        expect(viewModel.transcript, 'chicken and rice');
        expect(viewModel.hasVoiceTranscript, isTrue);
        expect(viewModel.proposal, proposal);
        verify(() => mockNutritionRepository.logAudio(any())).called(1);
        verifyNever(() => mockNutritionRepository.logText(any()));
      });

      test(
        'sends active proposal id and keeps proposal visible while correcting from audio',
        () async {
          const initialProposal = MealProposal(
            id: 'prop_1',
            title: 'Bread and butter',
            confidence: 0.85,
            requiresConfirmation: true,
            trustedAutoCommitEligible: false,
            nutrition: NutritionSnapshot(
              calories: 408,
              proteinGrams: 9.2,
              carbsGrams: 49,
              fatGrams: 19.4,
            ),
            items: [],
          );
          const updatedProposal = MealProposal(
            id: 'prop_1',
            title: 'Bread and butter',
            confidence: 0.85,
            requiresConfirmation: true,
            trustedAutoCommitEligible: false,
            nutrition: NutritionSnapshot(
              calories: 552,
              proteinGrams: 9.4,
              carbsGrams: 49,
              fatGrams: 35.6,
            ),
            items: [],
          );
          when(
            () => mockNutritionRepository.logText('bread and butter'),
          ).thenAnswer(
            (_) async => const AgentRunResult(
              kind: 'proposal',
              proposal: initialProposal,
              message: 'Meal proposal created.',
            ),
          );
          when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
          when(() => mockAudioRecorderService.stop()).thenAnswer(
            (_) async => const RecordedAudio(
              path: '/tmp/test.m4a',
              mimeType: 'audio/m4a',
              sizeBytes: 1024,
            ),
          );
          final correctionResult = Completer<VoiceMealRunResult>();
          when(
            () => mockNutritionRepository.logAudio(
              any(),
              activeProposalId: 'prop_1',
            ),
          ).thenAnswer((_) => correctionResult.future);

          await viewModel.submitText('bread and butter');
          expect(viewModel.state, VoiceLogState.proposalReady);
          expect(viewModel.proposal, initialProposal);

          await viewModel.toggleGlobalRecording();
          expect(viewModel.state, VoiceLogState.recording);
          expect(viewModel.proposal, initialProposal);

          final stopFuture = viewModel.toggleGlobalRecording();
          await Future.delayed(const Duration(milliseconds: 10));

          expect(viewModel.proposal, initialProposal);
          correctionResult.complete(
            const VoiceMealRunResult(
              transcript: 'no, the butter was 40 grams',
              provider: 'test',
              model: 'test-model',
              traceId: 'trace-2',
              result: AgentRunResult(
                kind: 'proposal',
                proposal: updatedProposal,
                message: 'Meal proposal updated.',
              ),
            ),
          );
          await stopFuture;

          expect(viewModel.state, VoiceLogState.proposalReady);
          expect(viewModel.transcript, 'no, the butter was 40 grams');
          expect(viewModel.hasVoiceTranscript, isTrue);
          expect(viewModel.proposal, updatedProposal);
          verify(
            () => mockNutritionRepository.logAudio(
              any(),
              activeProposalId: 'prop_1',
            ),
          ).called(1);
        },
      );

      test('starts a new recording from transcriptReady', () async {
        when(
          () => mockAudioRecorderService.hasPermission(),
        ).thenAnswer((_) async => true);
        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
        when(() => mockAudioRecorderService.stop()).thenAnswer(
          (_) async => const RecordedAudio(
            path: '/tmp/test.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 1024,
          ),
        );
        when(
          () => mockNutritionRepository.transcribeAudio(any()),
        ).thenAnswer((_) async => 'chicken and rice');

        await viewModel.toggleRecording();
        await viewModel.toggleRecording();
        expect(viewModel.state, VoiceLogState.transcriptReady);

        await viewModel.toggleRecording();

        expect(viewModel.state, VoiceLogState.recording);
        verify(() => mockAudioRecorderService.start()).called(2);
      });

      test('shows error on permission denied', () async {
        when(
          () => mockAudioRecorderService.start(),
        ).thenThrow(const RecorderException('permission_denied'));

        await viewModel.toggleRecording();

        expect(viewModel.state, VoiceLogState.error);
        expect(viewModel.errorMessage, contains('Microphone permission'));
      });

      test('shows error on transcription failure', () async {
        when(
          () => mockAudioRecorderService.hasPermission(),
        ).thenAnswer((_) async => true);
        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
        when(() => mockAudioRecorderService.stop()).thenAnswer(
          (_) async => const RecordedAudio(
            path: '/tmp/test.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 1024,
          ),
        );
        when(
          () => mockNutritionRepository.transcribeAudio(any()),
        ).thenThrow(Exception('network error'));

        await viewModel.toggleRecording(); // start
        expect(viewModel.state, VoiceLogState.recording);

        await viewModel.toggleRecording(); // stop
        await Future.delayed(const Duration(milliseconds: 100));

        expect(viewModel.state, VoiceLogState.error);
        expect(viewModel.errorMessage, contains('could not transcribe'));
      });

      test('shows error on voice meal failure', () async {
        when(
          () => mockAudioRecorderService.hasPermission(),
        ).thenAnswer((_) async => true);
        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
        when(() => mockAudioRecorderService.stop()).thenAnswer(
          (_) async => const RecordedAudio(
            path: '/tmp/test.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 1024,
          ),
        );
        when(
          () => mockNutritionRepository.logAudio(any()),
        ).thenThrow(Exception('network error'));

        await viewModel.toggleGlobalRecording();
        expect(viewModel.state, VoiceLogState.recording);

        await viewModel.toggleGlobalRecording();
        await Future.delayed(const Duration(milliseconds: 100));

        expect(viewModel.state, VoiceLogState.error);
        expect(
          viewModel.errorMessage,
          contains('turn that recording into a meal'),
        );
      });

      test('starts a new recording from error', () async {
        when(
          () => mockAudioRecorderService.start(),
        ).thenThrow(const RecorderException('permission_denied'));

        await viewModel.toggleRecording();
        expect(viewModel.state, VoiceLogState.error);

        when(() => mockAudioRecorderService.start()).thenAnswer((_) async {});
        await viewModel.toggleRecording();

        expect(viewModel.state, VoiceLogState.recording);
      });
    });

    group('submitText', () {
      test('transitions to proposalReady on proposal result', () async {
        const proposal = MealProposal(
          id: 'prop_1',
          title: 'Chicken and rice',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 500,
            proteinGrams: 30,
            carbsGrams: 60,
            fatGrams: 15,
          ),
          items: [],
        );
        when(
          () => mockNutritionRepository.logText('chicken and rice'),
        ).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            proposal: proposal,
            message: 'Meal proposal created.',
          ),
        );

        await viewModel.submitText('chicken and rice');

        expect(viewModel.state, VoiceLogState.proposalReady);
        expect(viewModel.proposal, proposal);
        expect(viewModel.message, 'Meal proposal created.');
        expect(viewModel.hasVoiceTranscript, isFalse);
        expect(viewModel.showProposalChangeSuccess, isFalse);
      });

      test(
        'sends active proposal id and replaces proposal from text correction',
        () async {
          const initialProposal = MealProposal(
            id: 'prop_1',
            title: 'Bread and butter',
            confidence: 0.85,
            requiresConfirmation: true,
            trustedAutoCommitEligible: false,
            nutrition: NutritionSnapshot(
              calories: 408,
              proteinGrams: 9.2,
              carbsGrams: 49,
              fatGrams: 19.4,
            ),
            items: [],
          );
          const updatedProposal = MealProposal(
            id: 'prop_1',
            title: 'Bread and butter',
            confidence: 0.85,
            requiresConfirmation: true,
            trustedAutoCommitEligible: false,
            nutrition: NutritionSnapshot(
              calories: 552,
              proteinGrams: 9.4,
              carbsGrams: 49,
              fatGrams: 35.6,
            ),
            items: [],
          );
          when(
            () => mockNutritionRepository.logText('bread and butter'),
          ).thenAnswer(
            (_) async => const AgentRunResult(
              kind: 'proposal',
              proposal: initialProposal,
              message: 'Meal proposal created.',
            ),
          );
          final correctionResult = Completer<AgentRunResult>();
          when(
            () => mockNutritionRepository.logText(
              'make the butter 40 grams',
              activeProposalId: 'prop_1',
            ),
          ).thenAnswer((_) => correctionResult.future);

          await viewModel.submitText('bread and butter');
          expect(viewModel.proposal, initialProposal);

          final correctionFuture = viewModel.submitText(
            'make the butter 40 grams',
          );
          await Future.delayed(const Duration(milliseconds: 10));

          expect(viewModel.state, VoiceLogState.agentRunning);
          expect(viewModel.proposal, initialProposal);

          correctionResult.complete(
            const AgentRunResult(
              kind: 'proposal',
              proposal: updatedProposal,
              message: 'Meal proposal updated.',
            ),
          );
          await correctionFuture;

          expect(viewModel.state, VoiceLogState.proposalReady);
          expect(viewModel.proposal, updatedProposal);
          expect(viewModel.showProposalChangeSuccess, isTrue);
          verify(
            () => mockNutritionRepository.logText(
              'make the butter 40 grams',
              activeProposalId: 'prop_1',
            ),
          ).called(1);

          await Future<void>.delayed(
            VoiceLogViewModel.proposalChangeSuccessDuration +
                const Duration(milliseconds: 100),
          );

          expect(viewModel.showProposalChangeSuccess, isFalse);
        },
      );

      test(
        'does not show change success when active proposal needs clarification',
        () async {
          const initialProposal = MealProposal(
            id: 'prop_1',
            title: 'Bread and butter',
            confidence: 0.85,
            requiresConfirmation: true,
            trustedAutoCommitEligible: false,
            nutrition: NutritionSnapshot(
              calories: 408,
              proteinGrams: 9.2,
              carbsGrams: 49,
              fatGrams: 19.4,
            ),
            items: [],
          );
          when(
            () => mockNutritionRepository.logText('bread and butter'),
          ).thenAnswer(
            (_) async => const AgentRunResult(
              kind: 'proposal',
              proposal: initialProposal,
              message: 'Meal proposal created.',
            ),
          );
          when(
            () => mockNutritionRepository.logText(
              'add red meat',
              activeProposalId: 'prop_1',
            ),
          ).thenAnswer(
            (_) async => const AgentRunResult(
              kind: 'clarification_required',
              proposal: initialProposal,
              message: 'Choose a food match for red meat.',
            ),
          );

          await viewModel.submitText('bread and butter');
          await viewModel.submitText('add red meat');

          expect(viewModel.state, VoiceLogState.clarificationRequired);
          expect(viewModel.proposal, initialProposal);
          expect(viewModel.showProposalChangeSuccess, isFalse);
        },
      );

      test('transitions to autoCommitted on meal result', () async {
        final meal = Meal(
          id: 'meal_1',
          title: 'Usual breakfast',
          occurredAt: DateTime.now(),
          nutrition: const NutritionSnapshot(
            calories: 400,
            proteinGrams: 20,
            carbsGrams: 50,
            fatGrams: 10,
          ),
          items: const [],
        );
        when(
          () => mockNutritionRepository.logText('usual breakfast'),
        ).thenAnswer(
          (_) async => AgentRunResult(
            kind: 'meal_committed',
            meal: meal,
            message: 'Meal logged from trusted template.',
          ),
        );

        await viewModel.submitText('usual breakfast');

        expect(viewModel.state, VoiceLogState.autoCommitted);
        expect(viewModel.autoCommittedMeal, meal);
      });

      test('transitions to error on failure', () async {
        when(
          () => mockNutritionRepository.logText(any()),
        ).thenThrow(Exception('network error'));

        await viewModel.submitText('test');

        expect(viewModel.state, VoiceLogState.error);
        expect(viewModel.errorMessage, contains('could not understand'));
      });

      test('does nothing when text is empty', () async {
        await viewModel.submitText('');
        expect(viewModel.state, VoiceLogState.idle);
      });

      test('keeps resolver candidate groups on clarification', () async {
        const groups = [
          FoodCandidateGroup(
            mention: FoodMention(
              originalText: 'queso',
              canonicalEnglishName: 'cheese',
              quantity: 100,
              unit: 'g',
              confidence: 0.92,
              marketProduct: false,
            ),
            candidates: [],
          ),
        ];
        when(
          () => mockNutritionRepository.logText('100 gramos de queso'),
        ).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'clarification_required',
            message: 'I could not confidently match every ingredient.',
            candidateGroups: groups,
          ),
        );

        await viewModel.submitText('100 gramos de queso');

        expect(viewModel.state, VoiceLogState.clarificationRequired);
        expect(viewModel.candidateGroups, groups);
      });
    });

    group('commitProposal', () {
      test('commits proposal and transitions to autoCommitted', () async {
        const proposal = MealProposal(
          id: 'prop_1',
          title: 'Chicken and rice',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 500,
            proteinGrams: 30,
            carbsGrams: 60,
            fatGrams: 15,
          ),
          items: [],
        );
        final meal = Meal(
          id: 'meal_1',
          title: 'Chicken and rice',
          occurredAt: DateTime.now(),
          nutrition: const NutritionSnapshot(
            calories: 500,
            proteinGrams: 30,
            carbsGrams: 60,
            fatGrams: 15,
          ),
          items: const [],
        );

        when(
          () => mockNutritionRepository.logText('chicken and rice'),
        ).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            proposal: proposal,
            message: 'Meal proposal created.',
          ),
        );
        when(
          () => mockNutritionRepository.commitProposal('prop_1'),
        ).thenAnswer((_) async => meal);

        await viewModel.submitText('chicken and rice');
        expect(viewModel.state, VoiceLogState.proposalReady);
        expect(viewModel.proposal, proposal);

        await viewModel.commitProposal();

        expect(viewModel.state, VoiceLogState.autoCommitted);
        expect(viewModel.autoCommittedMeal, meal);
        expect(viewModel.proposal, isNull);
      });

      test('does nothing when no proposal exists', () async {
        await viewModel.commitProposal();
        expect(viewModel.state, VoiceLogState.idle);
      });

      test('updates proposal items before commit', () async {
        const initialProposal = MealProposal(
          id: 'prop_1',
          title: 'Chicken and rice',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 410,
            proteinGrams: 31,
            carbsGrams: 28,
            fatGrams: 5,
          ),
          items: [
            MealItem(
              name: 'Chicken breast',
              quantity: 150,
              unit: 'g',
              calories: 248,
              proteinGrams: 46.5,
              carbsGrams: 0,
              fatGrams: 5.4,
              source: 'generic_usda',
            ),
          ],
        );
        const editedItems = [
          MealItem(
            name: 'Chicken breast',
            quantity: 100,
            unit: 'g',
            calories: 165,
            proteinGrams: 31,
            carbsGrams: 0,
            fatGrams: 3.6,
            source: 'generic_usda:manual_edit',
          ),
        ];
        const updatedProposal = MealProposal(
          id: 'prop_1',
          title: 'Chicken and rice',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 165,
            proteinGrams: 31,
            carbsGrams: 0,
            fatGrams: 3.6,
          ),
          items: editedItems,
        );
        when(
          () => mockNutritionRepository.logText('chicken and rice'),
        ).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            proposal: initialProposal,
            message: 'Meal proposal created.',
          ),
        );
        when(
          () => mockNutritionRepository.updateProposalItems(
            'prop_1',
            editedItems,
          ),
        ).thenAnswer((_) async => updatedProposal);

        await viewModel.submitText('chicken and rice');
        await viewModel.updateProposalItems(editedItems);

        expect(viewModel.state, VoiceLogState.proposalReady);
        expect(viewModel.proposal, updatedProposal);
        expect(viewModel.showProposalChangeSuccess, isTrue);
        verify(
          () => mockNutritionRepository.updateProposalItems(
            'prop_1',
            editedItems,
          ),
        ).called(1);
      });

      test('does not show change success for materially unchanged edits',
          () async {
        const initialItems = [
          MealItem(
            name: 'Chicken breast',
            quantity: 100,
            unit: 'g',
            calories: 165,
            proteinGrams: 31,
            carbsGrams: 0,
            fatGrams: 3.6,
            source: 'generic_usda',
            externalSource: 'usda_fdc',
            externalId: '171477',
          ),
        ];
        const initialProposal = MealProposal(
          id: 'prop_1',
          title: 'Chicken',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 165,
            proteinGrams: 31,
            carbsGrams: 0,
            fatGrams: 3.6,
          ),
          items: initialItems,
        );
        const editedItems = [
          MealItem(
            name: 'Chicken breast',
            quantity: 100,
            unit: 'g',
            calories: 165,
            proteinGrams: 31,
            carbsGrams: 0,
            fatGrams: 3.6,
            source: 'generic_usda:manual_edit',
            externalSource: 'usda_fdc',
            externalId: '171477',
          ),
        ];
        const updatedProposal = MealProposal(
          id: 'prop_1',
          title: 'Chicken',
          confidence: 0.85,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 165,
            proteinGrams: 31,
            carbsGrams: 0,
            fatGrams: 3.6,
          ),
          items: editedItems,
        );
        when(
          () => mockNutritionRepository.logText('chicken'),
        ).thenAnswer(
          (_) async => const AgentRunResult(
            kind: 'proposal',
            proposal: initialProposal,
            message: 'Meal proposal created.',
          ),
        );
        when(
          () => mockNutritionRepository.updateProposalItems(
            'prop_1',
            editedItems,
          ),
        ).thenAnswer((_) async => updatedProposal);

        await viewModel.submitText('chicken');
        await viewModel.updateProposalItems(editedItems);

        expect(viewModel.state, VoiceLogState.proposalReady);
        expect(viewModel.proposal, updatedProposal);
        expect(viewModel.message, isNull);
        expect(viewModel.showProposalChangeSuccess, isFalse);
      });

      test('creates proposal from edited items when no proposal exists',
          () async {
        const bread = MealItem(
          name: 'Bread',
          quantity: 100,
          unit: 'g',
          calories: 265,
          proteinGrams: 7,
          carbsGrams: 1,
          fatGrams: 8,
          source: 'off:manual_edit',
        );
        const createdProposal = MealProposal(
          id: 'manual_prop',
          title: 'Bread',
          confidence: 0.9,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 265,
            proteinGrams: 7,
            carbsGrams: 1,
            fatGrams: 8,
          ),
          items: [bread],
        );
        when(
          () => mockNutritionRepository.createProposalFromItems(
            phrase: any(named: 'phrase'),
            items: any(named: 'items'),
          ),
        ).thenAnswer((_) async => createdProposal);

        await viewModel.updateProposalItems([bread]);

        expect(viewModel.state, VoiceLogState.proposalReady);
        expect(viewModel.proposal, createdProposal);
        final captured = verify(
          () => mockNutritionRepository.createProposalFromItems(
            phrase: any(named: 'phrase'),
            items: captureAny(named: 'items'),
          ),
        ).captured.single as List<MealItem>;
        expect(captured, [bread]);
        verifyNever(
            () => mockNutritionRepository.updateProposalItems(any(), any()));
      });
    });

    group('candidate selection', () {
      test('creates proposal with candidate index 9', () async {
        final group = _candidateGroup(
          originalText: 'queso',
          canonicalEnglishName: 'cheese',
          candidates: _candidateItems('Cheese', count: 10),
        );
        const proposal = MealProposal(
          id: 'prop_candidates',
          title: 'Cheese',
          confidence: 0.82,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 109,
            proteinGrams: 7,
            carbsGrams: 1,
            fatGrams: 9,
          ),
          items: [],
        );
        when(
          () => mockNutritionRepository.logText('100 gramos de queso'),
        ).thenAnswer(
          (_) async => AgentRunResult(
            kind: 'clarification_required',
            message: 'Choose a food match.',
            candidateGroups: [group],
          ),
        );
        when(
          () => mockNutritionRepository.createProposalFromItems(
            phrase: any(named: 'phrase'),
            items: any(named: 'items'),
          ),
        ).thenAnswer((_) async => proposal);

        await viewModel.submitText('100 gramos de queso');
        await viewModel.selectCandidate(group, group.candidates[9]);

        final captured = verify(
          () => mockNutritionRepository.createProposalFromItems(
            phrase: '100 gramos de queso',
            items: captureAny(named: 'items'),
          ),
        ).captured.single as List<MealItem>;
        expect(captured, [group.candidates[9]]);
        expect(viewModel.state, VoiceLogState.proposalReady);
        expect(viewModel.proposal, proposal);
        expect(viewModel.candidateGroups, [group]);
        expect(viewModel.selectedCandidateFor(group), group.candidates[9]);
      });

      test(
        'waits for every unresolved group before creating proposal',
        () async {
          final cheeseGroup = _candidateGroup(
            originalText: 'queso',
            canonicalEnglishName: 'cheese',
            candidates: _candidateItems('Cheese', count: 2),
          );
          final breadGroup = _candidateGroup(
            originalText: 'pan',
            canonicalEnglishName: 'bread',
            candidates: _candidateItems('Bread', count: 2),
          );
          const proposal = MealProposal(
            id: 'prop_multi',
            title: 'Cheese and bread',
            confidence: 0.82,
            requiresConfirmation: true,
            trustedAutoCommitEligible: false,
            nutrition: NutritionSnapshot(
              calories: 250,
              proteinGrams: 12,
              carbsGrams: 30,
              fatGrams: 8,
            ),
            items: [],
          );
          when(() => mockNutritionRepository.logText('queso y pan')).thenAnswer(
            (_) async => AgentRunResult(
              kind: 'clarification_required',
              message: 'Choose food matches.',
              candidateGroups: [cheeseGroup, breadGroup],
            ),
          );
          when(
            () => mockNutritionRepository.createProposalFromItems(
              phrase: any(named: 'phrase'),
              items: any(named: 'items'),
            ),
          ).thenAnswer((_) async => proposal);

          await viewModel.submitText('queso y pan');
          await viewModel.selectCandidate(
            cheeseGroup,
            cheeseGroup.candidates[1],
          );

          verifyNever(
            () => mockNutritionRepository.createProposalFromItems(
              phrase: any(named: 'phrase'),
              items: any(named: 'items'),
            ),
          );

          await viewModel.selectCandidate(breadGroup, breadGroup.candidates[1]);

          final captured = verify(
            () => mockNutritionRepository.createProposalFromItems(
              phrase: 'queso y pan',
              items: captureAny(named: 'items'),
            ),
          ).captured.single as List<MealItem>;
          expect(captured, [
            cheeseGroup.candidates[1],
            breadGroup.candidates[1],
          ]);
          expect(viewModel.state, VoiceLogState.proposalReady);
        },
      );

      test('defaults resolved group selection and allows editing it', () async {
        final selectedCheese = _mealItem(
          name: 'Cheese 1',
          externalId: 'cheese_1',
          canonicalName: 'cheese',
        );
        final alternateCheese = _mealItem(
          name: 'Cheese 2',
          externalId: 'cheese_2',
          canonicalName: 'cheese',
        );
        final group = _candidateGroup(
          originalText: 'queso',
          canonicalEnglishName: 'cheese',
          candidates: [selectedCheese, alternateCheese],
        );
        const proposal = MealProposal(
          id: 'prop_resolved_edit',
          title: 'Edited cheese',
          confidence: 0.82,
          requiresConfirmation: true,
          trustedAutoCommitEligible: false,
          nutrition: NutritionSnapshot(
            calories: 102,
            proteinGrams: 7,
            carbsGrams: 1,
            fatGrams: 8,
          ),
          items: [],
        );
        when(
          () => mockNutritionRepository.logText('100 gramos de queso'),
        ).thenAnswer(
          (_) async => AgentRunResult(
            kind: 'clarification_required',
            message: 'Review food matches.',
            resolvedItems: [selectedCheese],
            candidateGroups: [group],
          ),
        );
        when(
          () => mockNutritionRepository.createProposalFromItems(
            phrase: any(named: 'phrase'),
            items: any(named: 'items'),
          ),
        ).thenAnswer((_) async => proposal);

        await viewModel.submitText('100 gramos de queso');

        expect(viewModel.isCandidateSelected(group, selectedCheese), isTrue);
        expect(viewModel.selectedCandidateFor(group), selectedCheese);

        await viewModel.selectCandidate(group, alternateCheese);

        final captured = verify(
          () => mockNutritionRepository.createProposalFromItems(
            phrase: '100 gramos de queso',
            items: captureAny(named: 'items'),
          ),
        ).captured.single as List<MealItem>;
        expect(captured, [alternateCheese]);
        expect(viewModel.state, VoiceLogState.proposalReady);
      });

      test(
        'uses visible clarification options while keeping full proposal candidates',
        () async {
          final rice = _mealItem(
            name: 'Cooked rice',
            externalId: 'rice_1',
            canonicalName: 'rice',
          );
          final riceGroup = _candidateGroup(
            originalText: '100 grams of rice',
            canonicalEnglishName: 'rice',
            candidates: [rice, _mealItem(name: 'Rice 2', externalId: 'rice_2')],
          );
          final beefGroup = _candidateGroup(
            originalText: '100 grams of beef',
            canonicalEnglishName: 'beef',
            candidates: _candidateItems('Beef', count: 2),
          );
          final selectedBeef = beefGroup.candidates[1];
          final partialProposal = MealProposal(
            id: 'prop_partial',
            title: 'Rice',
            confidence: 0.68,
            requiresConfirmation: true,
            trustedAutoCommitEligible: false,
            nutrition: const NutritionSnapshot(
              calories: 100,
              proteinGrams: 7,
              carbsGrams: 1,
              fatGrams: 8,
            ),
            items: [rice],
          );
          final updatedProposal = MealProposal(
            id: 'prop_partial',
            title: 'Rice and beef',
            confidence: 0.82,
            requiresConfirmation: true,
            trustedAutoCommitEligible: false,
            nutrition: const NutritionSnapshot(
              calories: 201,
              proteinGrams: 14,
              carbsGrams: 2,
              fatGrams: 16,
            ),
            items: [rice, selectedBeef],
          );
          when(
            () => mockNutritionRepository.logText('rice and beef'),
          ).thenAnswer(
            (_) async => AgentRunResult(
              kind: 'clarification_required',
              message: 'Choose a food match for beef.',
              proposal: partialProposal,
              resolvedItems: [rice],
              clarificationOptions: [beefGroup],
              candidateGroups: [riceGroup, beefGroup],
            ),
          );
          when(
            () => mockNutritionRepository.updateProposalItems(
              'prop_partial',
              any(),
            ),
          ).thenAnswer((_) async => updatedProposal);

          await viewModel.submitText('rice and beef');

          expect(viewModel.proposal, partialProposal);
          expect(viewModel.clarificationOptions, [beefGroup]);
          expect(viewModel.candidateGroups, [riceGroup, beefGroup]);
          expect(viewModel.isCandidateSelected(riceGroup, rice), isTrue);

          await viewModel.selectCandidate(beefGroup, selectedBeef);

          final captured = verify(
            () => mockNutritionRepository.updateProposalItems(
              'prop_partial',
              captureAny(),
            ),
          ).captured.single as List<MealItem>;
          expect(captured, [rice, selectedBeef]);
          expect(viewModel.state, VoiceLogState.proposalReady);
          expect(viewModel.proposal, updatedProposal);
        },
      );
    });

    group('clearResult', () {
      test('resets all state', () async {
        viewModel.updateTranscript('test');
        viewModel.clearResult();

        expect(viewModel.state, VoiceLogState.idle);
        expect(viewModel.proposal, isNull);
        expect(viewModel.autoCommittedMeal, isNull);
        expect(viewModel.message, isNull);
        expect(viewModel.errorMessage, isNull);
        expect(viewModel.transcript, isEmpty);
      });
    });

    group('retry', () {
      test('clears error and returns to idle', () async {
        viewModel.updateTranscript('test');

        // Simulate error state
        when(
          () => mockNutritionRepository.logText(any()),
        ).thenThrow(Exception('error'));
        await viewModel.submitText();
        expect(viewModel.state, VoiceLogState.error);

        viewModel.retry();

        expect(viewModel.state, VoiceLogState.idle);
        expect(viewModel.errorMessage, isNull);
      });
    });
  });
}

FoodCandidateGroup _candidateGroup({
  required String originalText,
  required String canonicalEnglishName,
  required List<MealItem> candidates,
}) {
  return FoodCandidateGroup(
    mention: FoodMention(
      originalText: originalText,
      canonicalEnglishName: canonicalEnglishName,
      quantity: 100,
      unit: 'g',
      confidence: 0.92,
      marketProduct: false,
    ),
    candidates: candidates,
  );
}

List<MealItem> _candidateItems(String prefix, {required int count}) {
  return [
    for (var index = 0; index < count; index++)
      _mealItem(
        name: '$prefix ${index + 1}',
        calories: 100 + index,
        externalId: '${prefix.toLowerCase()}_${index + 1}',
      ),
  ];
}

MealItem _mealItem({
  required String name,
  int calories = 100,
  String? externalId,
  String? canonicalName,
}) {
  return MealItem(
    name: name,
    quantity: 100,
    unit: 'g',
    calories: calories,
    proteinGrams: 7,
    carbsGrams: 1,
    fatGrams: 8,
    source: 'open_food_facts',
    canonicalName: canonicalName,
    externalSource: 'Open Food Facts',
    externalId: externalId,
    confidence: 0.9,
    resolvedGrams: 100,
  );
}
