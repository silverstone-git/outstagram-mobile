// Golden fixtures for the Dart exam engine. Runs the web's real TypeScript engine over fixed exams and
// answers, and writes what it computes to test/fixtures/exam_golden.json. test/exam_engine_test.dart must
// reproduce every number. Regenerate after engine.ts changes:
//   bun tool/exam_golden.ts          (from outstagram_mobile/, with ../outstagram-web checked out)
import { writeFileSync } from 'node:fs';
import {
  maxScore, normalizeExamConfig, prepareQuestions, scoreExam, type DraftAnswer,
} from '../../outstagram-web/src/features/exams/engine.ts';
import type { ExamConfig, Question } from '../../outstagram-web/src/features/exams/types.ts';

const NOW = 1_764_000_000_000;
Date.now = () => NOW;

const opts = (n = 4) => Array.from({ length: n }, (_, i) => ({ label: i + 1, value: `$x_${i + 1}$ option ${i + 1}` }));
const mcq = (id: string, topic: string, answer: number): Question =>
  ({ id, type: 'MCQ', question: `Q ${id} $\\\\alpha$`, options: opts(), answer_label: answer, topic, explanation: 'because' });
const msq = (id: string, topic: string, answers: number[]): Question =>
  ({ id, type: 'MSQ', question: `MSQ ${id}`, options: opts(), answer_labels: answers, topic, explanation: '' });
const natRange = (id: string, topic: string, min: number, max: number): Question =>
  ({ id, type: 'NAT', question: `NAT ${id}`, answer_range: { min, max }, topic, explanation: '' });
const natValue = (id: string, topic: string, v: string): Question =>
  ({ id, type: 'NAT', question: `NAT ${id}`, answer_value: v, topic, explanation: '' });

interface Case {
  name: string;
  config: ExamConfig;
  answers: Record<string, DraftAnswer>;
  timers: Record<string, number>;
  startedAt: number;
}

const cases: Case[] = [
  {
    name: 'gate-like two sections with negatives',
    config: {
      name: 'GATE fixture',
      settings: { timerHours: 3, timerMinutes: 0, shuffleQuestions: false, shuffleOptions: false },
      sections: [
        { id: 's1', name: '1 Mark', marking: { positive: 1, negative: 0.33 }, questions: [
          mcq('a1', 'Quantum', 2), mcq('a2', 'Quantum', 3), mcq('a3', 'EM', 1), msq('a4', 'EM', [1, 3]), natRange('a5', 'Thermo', 1.5, 1.6),
        ] },
        { id: 's2', name: '2 Mark', marking: { positive: 2, negative: 0.66 }, questions: [
          mcq('b1', 'Quantum', 4), msq('b2', 'Thermo', [2, 4, 1]), natValue('b3', 'EM', '0.25'), mcq('b4', 'Optics', 1),
        ] },
      ],
    },
    answers: {
      a1: { label: 2 }, a2: { label: 1, isFlagged: true }, a4: { labels: [3, 1] }, a5: { text: '1.55' },
      b1: { label: 4 }, b2: { labels: [1, 2] }, b3: { text: '0.250' }, b4: { label: null, isFlagged: true },
    },
    timers: { a1: 30.4, a2: 95.6, a3: 3, a4: 61.2, a5: 120, b1: 40, b2: 200.5, b3: 75, b4: 2 },
    startedAt: NOW - 900_000,
  },
  {
    name: 'csir-like maxAttempts caps the first N attempted',
    config: {
      name: 'CSIR fixture',
      sections: [
        { id: 'pb', name: 'Part B', marking: { positive: 3.5, negative: 0.875 }, questions: [mcq('p1', 'Math', 1), mcq('p2', 'Math', 2)] },
        { id: 'pc', name: 'Part C', marking: { positive: 5, negative: 1.25 }, maxAttempts: 2, questions: [
          mcq('c1', 'QM', 1), mcq('c2', 'QM', 2), mcq('c3', 'QM', 3), mcq('c4', 'Stat', 4), mcq('c5', 'Stat', 1),
        ] },
      ],
    },
    answers: { p1: { label: 1 }, p2: { label: 3 }, c1: { label: 2 }, c3: { label: 3 }, c4: { label: 4 }, c5: { label: 1 } },
    timers: { p1: 10, p2: 20, c1: 300, c2: 0, c3: 50, c4: 400, c5: 5 },
    startedAt: NOW - 1_200_000,
  },
  {
    name: 'legacy flat questions, global marking, questionCount cap, missing ids',
    config: {
      name: 'Legacy fixture',
      settings: { timerHours: 0, timerMinutes: 45, shuffleQuestions: false, shuffleOptions: false, questionCount: 4, positiveMarking: 3, negativeMarking: 1 },
      questions: [
        { question: 'no id 1', options: opts(), answer_label: 1, topic: 'Mech', explanation: '' } as Question,
        { question: 'no id 2', options: opts(), answer_label: 2, topic: 'Mech', explanation: '' } as Question,
        { question: 'no id 3', type: 'NAT', answer_range: { min: -1, max: 1 }, topic: 'Elec', explanation: '' } as Question,
        { question: 'no id 4', options: opts(), answer_label: 4, topic: 'Elec', explanation: '' } as Question,
        { question: 'no id 5 (cut by questionCount)', options: opts(), answer_label: 1, topic: 'Mech', explanation: '' } as Question,
      ],
    },
    answers: { 'q-0': { label: 1 }, 'q-1': { label: 1 }, 'q-2': { text: '-1' }, 'q-4': { label: 1 } },
    timers: { 'q-0': 12, 'q-1': 13, 'q-2': 90, 'q-3': 1 },
    startedAt: NOW - 300_000,
  },
  {
    name: 'NAT parsing edge cases (JS parseFloat semantics)',
    config: {
      name: 'NAT fixture',
      sections: [{ id: 'n', name: 'NAT', marking: { positive: 2, negative: 0.5 }, questions: [
        natRange('n1', 'T', 1, 2), natRange('n2', 'T', 1, 2), natRange('n3', 'T', 1, 2), natValue('n4', 'T', '3'),
        natValue('n5', 'T', '1e3'), natRange('n6', 'T', 0, 0), natValue('n7', 'T', '2.5'), natRange('n8', 'U', 5, 6),
      ] }],
    },
    answers: {
      n1: { text: '2' }, n2: { text: '1e' }, n3: { text: 'abc' }, n4: { text: '3.0' }, n5: { text: '1000' },
      n6: { text: '-0' }, n7: { text: '2.5.1' }, n8: { text: '' },
    },
    timers: { n1: 5, n2: 5, n3: 5, n4: 5, n5: 5, n6: 5, n7: 5, n8: 5 },
    startedAt: NOW - 60_000,
  },
  {
    name: 'nothing answered',
    config: { name: 'Empty fixture', sections: [{ id: 'e', name: 'E', marking: { positive: 1, negative: 0.25 }, questions: [mcq('e1', 'A', 1), msq('e2', 'B', [2])] }] },
    answers: {},
    timers: {},
    startedAt: NOW - 10_000,
  },
];

const out = cases.map((c) => {
  const config = normalizeExamConfig(structuredClone(c.config));
  const questions = prepareQuestions(config);
  const result = scoreExam(config, questions, c.answers, c.timers, c.startedAt);
  return {
    name: c.name, config: c.config, answers: c.answers, timers: c.timers, startedAt: c.startedAt, now: NOW,
    expected: {
      questionIds: questions.map((q) => q.id),
      maxScore: maxScore(config, questions),
      ...result,
      originalQuestions: undefined,
      originalConfig: undefined,
    },
  };
});

writeFileSync(new URL('../test/fixtures/exam_golden.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${out.length} cases`);
