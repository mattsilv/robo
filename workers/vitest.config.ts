import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
	test: {
		poolOptions: {
			workers: {
				wrangler: { configPath: './wrangler.toml' },
				miniflare: {
					d1Databases: ['DB'],
					bindings: {
						JWT_SECRET: 'test-jwt-secret-for-vitest-only',
						APPLE_CLIENT_ID: 'com.silv.Robo.web.test',
					},
				},
			},
		},
	},
});
