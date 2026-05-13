# Leona Server

This directory is intentionally kept as a placeholder.

The Leona hosted API/backend implementation is not open source. It contains evidence ingestion, provenance processing, tenant controls, operational controls, deployment assumptions, and security-sensitive server-side behavior. Publishing that code would weaken the security model by making the server-side bypass surface easier to study.

The public Android SDK remains fully usable by customers when configured with a Leona API key and the Leona hosted endpoints. Leona hosted endpoints return environment evidence, provenance, and compatible evidence-report fields; final allow, challenge, deny, or other business actions belong to the customer backend policy, not to code shipped in the APK.
