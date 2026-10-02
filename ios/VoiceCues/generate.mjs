import { parseEnv } from 'node:util';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const privateRoot = '/Users/jaibhagat/code/prismml/Bonsai-demo-private';
const workspaceRoot = '/Users/jaibhagat/code/prismml/bonsai-workspace';
const privateEnv = parseEnv(fs.readFileSync(path.join(privateRoot, '.env'), 'utf8'));
const workspaceEnv = parseEnv(fs.readFileSync(path.join(workspaceRoot, '.env'), 'utf8'));
const token = privateEnv.AI_GATEWAY_API_KEY;
const voice = workspaceEnv.BONSAI_DOLLY_VOICE_ID;
if (!token || !voice) throw Error('Existing gateway token or configured voice is unavailable');
const req = createRequire(path.join(workspaceRoot, 'scripts/workspace-tools/package.json'));
const { experimental_generateSpeech: generateSpeech } = await import(pathToFileURL(req.resolve('ai')));
const { createGateway } = await import(pathToFileURL(req.resolve('@ai-sdk/gateway')));
const gateway = createGateway({ apiKey: token });
const out = path.dirname(new URL(import.meta.url).pathname);
const lines = [
  ['fr', 'opening', 'Entre dans le round. Pose ton téléphone. Respire. On commence.'],
  ['en', 'opening', 'Enter the round. Set down your phone. Breathe. We begin.'],
  ['fr', 'probe_mid_cue', 'Jab pour ouvrir. Deux ou trois coups, puis sors en angle.'],
  ['en', 'probe_mid_cue', 'Probe with the jab. Two or three punches, then exit on an angle.'],
  ['fr', 'rest_speech', 'Récupération. Respire.'],
  ['en', 'rest_speech', 'Rest. Breathe.'],
  ['fr', 'mobility_cue', 'Mobilité. Bouge les épaules, les hanches et les chevilles.'],
  ['en', 'mobility_cue', 'Mobility. Move your shoulders, hips and ankles.'],
  ['fr', 'squats_cue', 'Squats. Descends avec contrôle, puis remonte.'],
  ['en', 'squats_cue', 'Squats. Lower with control, then stand.'],
  ['fr', 'lunges_cue', 'Fentes. Alterne les jambes et garde ton équilibre.'],
  ['en', 'lunges_cue', 'Lunges. Alternate legs and keep your balance.'],
  ['fr', 'shadowboxing_cue', 'Boxe dans le vide. Jab léger, garde haute, petits pas.'],
  ['en', 'shadowboxing_cue', 'Shadowbox. Light jab, hands up, small steps.'],
  ['fr', 'round_speech', 'Jab, combinaison, sortie en angle.'],
  ['en', 'round_speech', 'Jab, combination, angle exit.'],
  ['fr', 'guard_round_speech', 'Après chaque coup, reviens en garde.'],
  ['en', 'guard_round_speech', 'Return to guard after every punch.'],
  ['fr', 'free_round_speech', 'Round libre. Reste attentif à ta garde et à tes appuis.'],
  ['en', 'free_round_speech', 'Open round. Stay aware of your guard and footwork.'],
  ['fr', 'probe_late_cue', "Reviens en garde, change d'angle, puis recommence."],
  ['en', 'probe_late_cue', 'Recover your guard, change angle, then repeat.'],
  ['fr', 'guard_mid_cue', 'Après le jab, ramène la main tout de suite.'],
  ['en', 'guard_mid_cue', 'After the jab, bring your hand straight back.'],
  ['fr', 'guard_late_cue', 'Garde les mains en place entre les coups.'],
  ['en', 'guard_late_cue', 'Keep your hands in position between punches.'],
  ['fr', 'free_mid_cue', 'Une minute écoulée. Continue à ton rythme.'],
  ['en', 'free_mid_cue', 'One minute down. Keep your rhythm.'],
  ['fr', 'free_late_cue', 'Dernière minute. Reste propre dans tes mouvements.'],
  ['en', 'free_late_cue', 'Final minute. Keep your movements clean.'],
  ['fr', 'cooldown_speech', 'Retour au calme. Ralentis et respire.'],
  ['en', 'cooldown_speech', 'Cool down. Slow down and breathe.'],
];
for (const [language, key, value] of lines) {
  const dest = path.join(out, `${language}_${key}.mp3`);
  if (fs.existsSync(dest)) { console.log(`${language}_${key}: cached`); continue; }
  try {
    const result = await generateSpeech({
      model: gateway.speechModel('fish-audio/s2.1-pro'),
      text: value, voice, outputFormat: 'mp3', maxRetries: 0,
      abortSignal: AbortSignal.timeout(120000),
    });
    fs.writeFileSync(dest, Buffer.from(result.audio.base64, 'base64'));
    console.log(`${language}_${key}: generated`);
  } catch (error) {
    console.error(`${language}_${key}: ${String(error.message).replaceAll(token, '[REDACTED]').slice(0, 240)}`);
    process.exitCode = 1;
    break;
  }
}
if (!process.exitCode) {
  const manifest = {
    model: 'fish-audio/s2.1-pro',
    provider: 'Vercel AI Gateway',
    voice_config: 'BONSAI_DOLLY_VOICE_ID',
    billed_cost_usd: null,
    cost_status: 'Gateway response did not expose billed cost; unknown is not zero.',
    generated_audio: lines.map(([language, cueKey, text]) => {
      const filename = `${language}_${cueKey}.mp3`;
      const data = fs.readFileSync(path.join(out, filename));
      return { language, cue_key: cueKey, text, filename, bytes: data.length,
        sha256: crypto.createHash('sha256').update(data).digest('hex') };
    }),
  };
  fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
}
