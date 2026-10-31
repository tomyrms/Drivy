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
  assert.deepEqual(Object.keys(workflows.get('qualification-checks.yml').jobs).sort(), ['changes', 'documentation', 'server', 'web']);
  assert.deepEqual(Object.keys(workflows.get('qualification-checks.yml').on), ['workflow_call']);
});

test('accès Messages physique explicite identique dans tests natifs et IPA', () => {
  const wrapper = workflows.get('refonte-checks.yml');
  const final = workflows.get('validation-finale.yml');
  assert.equal(wrapper.on.workflow_dispatch.inputs.messaging_qualification.default, false);
  assert.equal(wrapper.jobs.final.with.messaging_qualification, '${{ inputs.messaging_qualification }}');
  assert.equal(final.on.workflow_call.inputs.messaging_qualification.default, false);
  for (const name of ['ios', 'ipa']) {
    assert.equal(final.jobs[name].with.messaging_qualification, '${{ inputs.messaging_qualification }}');
  }
  for (const file of ['refonte-ios.yml', 'ipa-essai.yml']) {
    const workflow = workflows.get(file);
    assert.equal(workflow.on.workflow_dispatch.inputs.messaging_qualification.default, false);
    assert.equal(workflow.on.workflow_call.inputs.messaging_qualification.default, false);
    const job = Object.values(workflow.jobs)[0];
    assert.equal(job.env.DRIVY_MESSAGING_QUALIFICATION, "${{ inputs.messaging_qualification && '1' || '0' }}");
  }
});

test('la sélection par chemins ne dispense jamais une qualification', () => {
  const wrapper = workflows.get('refonte-checks.yml');
  const final = workflows.get('validation-finale.yml');
  const checks = workflows.get('qualification-checks.yml');
  // Seul le point d'entrée push/PR demande la sélection ; la finale ne la transmet pas : défaut faux, toutes les suites.
  assert.equal(wrapper.jobs.checks.with.select_by_paths, "${{ github.event_name != 'workflow_dispatch' }}");
  assert.equal('select_by_paths' in final.jobs.checks.with, false);
  assert.equal(checks.on.workflow_call.inputs.select_by_paths.default, false);
  assert.equal(checks.jobs.server.needs, 'changes');
  assert.equal(checks.jobs.web.needs, 'changes');
  assert.match(checks.jobs.server.if, /needs\.changes\.outputs\.server == 'true'/);
  assert.match(checks.jobs.web.if, /needs\.changes\.outputs\.web == 'true'/);
  // La vérification documentaire reste inconditionnelle.
  assert.equal(checks.jobs.documentation.needs, undefined);
});

test('seuls les push et pull requests dépassés sont annulés, jamais master ni un lancement explicite ou une qualification', () => {
  const cancelling = [['refonte-checks.yml', "github.event_name != 'workflow_dispatch' && github.ref != 'refs/heads/master'"],
    ['ipa-essai.yml', "github.event_name == 'push' && github.ref != 'refs/heads/master'"],
    ['school-opening-e2e.yml', "github.event_name == 'pull_request' || github.event_name == 'push' && github.ref != 'refs/heads/master'"]];
  for (const [name, condition] of cancelling) {
    assert.equal(workflows.get(name).concurrency['cancel-in-progress'], '${{ ' + condition + ' }}', name);
  }
  for (const name of ['refonte-ios.yml', 'qualification-checks.yml', 'validation-finale.yml']) {
    assert.equal(workflows.get(name).concurrency['cancel-in-progress'], false, name);
  }
});

test('un lancement iOS explicite ne dépend pas de la branche : ni file d’attente ni annulation', () => {
  const ios = workflows.get('refonte-ios.yml');
  assert.doesNotMatch(ios.concurrency.group, /github\.ref/);
  assert.match(ios.concurrency.group, /inputs\.qualification_sha \|\| github\.run_id/);
  const ipa = workflows.get('ipa-essai.yml');
  assert.match(ipa.concurrency.group, /github\.run_id/);
});
