import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import test from 'node:test';
import { parseDocument } from 'yaml';

const directory = new URL('../../.github/workflows/', import.meta.url);
const workflows = new Map(readdirSync(directory).filter(name => name.endsWith('.yml')).map(name => {
  const parsed = parseDocument(readFileSync(new URL(name, directory), 'utf8'), { uniqueKeys: true });
  assert.deepEqual(parsed.errors, [], `YAML invalide : ${name}`);
  return [name, parsed.toJS()];
}));

function graphOf(documents) {
  return new Map([...documents].map(([name, doc]) => [name, Object.values(doc.jobs)
    .filter(job => job.uses?.startsWith('./.github/workflows/'))
    .map(job => job.uses.split('/').at(-1))]));
}

function acyclic(graph) {
  const visited = new Set();
  function visit(name, stack = new Set()) {
    assert.ok(!stack.has(name), `Cycle de workflows : ${name}`);
    if (visited.has(name)) return;
    assert.ok(graph.has(name), `Workflow absent : ${name}`);
    const next = new Set(stack).add(name);
    for (const child of graph.get(name)) visit(child, next);
    visited.add(name);
  }
  for (const name of graph.keys()) visit(name);
}

test('le graphe réel est sans cycle et une régression récursive est refusée', () => {
  const graph = graphOf(workflows);
  acyclic(graph);
  const recursive = new Map(graph);
  recursive.set('qualification-checks.yml', ['refonte-checks.yml']);
  assert.throws(() => acyclic(recursive), /Cycle/);
});

test('chaque appel local respecte les inputs du contrat workflow_call', () => {
  for (const document of workflows.values()) {
    for (const job of Object.values(document.jobs)) {
      if (!job.uses?.startsWith('./.github/workflows/')) continue;
      const target = workflows.get(job.uses.split('/').at(-1));
      assert.ok(target?.on?.workflow_call, 'Cible non réutilisable');
      const inputs = target.on.workflow_call.inputs ?? {};
      for (const name of Object.keys(job.with ?? {})) assert.ok(name in inputs, `Input inconnu : ${name}`);
      for (const [name, input] of Object.entries(inputs)) {
        if (input.required) assert.ok(name in (job.with ?? {}), `Input obligatoire absent : ${name}`);
      }
      assert.notEqual(document.concurrency?.group, target.concurrency?.group, 'Concurrence parent/enfant identique');
    }
  }
});

test('entrée historique conserve push/PR et bascule explicite exclusivement manuelle', () => {
  const wrapper = workflows.get('refonte-checks.yml');
  assert.deepEqual(wrapper.on.push.branches, ['master', 'codex/**', 'claude/**']);
  assert.deepEqual(wrapper.on.pull_request.branches, ['master']);
  assert.equal(wrapper.on.workflow_dispatch.inputs.final_campaign.default, false);
  assert.equal(wrapper.jobs.checks.uses, './.github/workflows/qualification-checks.yml');
  assert.equal(wrapper.jobs.final.uses, './.github/workflows/validation-finale.yml');
  assert.equal(wrapper.jobs.final.if, "github.event_name == 'workflow_dispatch' && inputs.final_campaign == true");
  assert.equal(wrapper.jobs.checks.if, "github.event_name != 'workflow_dispatch' || inputs.final_campaign != true");
  assert.ok(Object.values(wrapper.jobs).every(job => !job.steps), 'Le wrapper duplique une suite');
});

test('finale transmet le SHA figé sans appeler le wrapper', () => {
  const final = workflows.get('validation-finale.yml');
  assert.equal(final.jobs.checks.uses, './.github/workflows/qualification-checks.yml');
  for (const name of ['checks', 'browser', 'ios', 'ipa']) {
    assert.equal(final.jobs[name].with.qualification_sha, '${{ needs.resolve.outputs.sha }}');
    assert.equal(final.jobs[name].needs, 'resolve');
  }
  assert.deepEqual(Object.keys(workflows.get('qualification-checks.yml').jobs).sort(), ['documentation', 'server', 'web']);
  assert.deepEqual(Object.keys(workflows.get('qualification-checks.yml').on), ['workflow_call']);
});
