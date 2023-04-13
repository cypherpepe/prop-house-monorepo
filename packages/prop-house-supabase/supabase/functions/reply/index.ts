import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import prophouse from 'https://esm.sh/@prophouse/communities@0.1.4';
import { ethers } from 'https://esm.sh/ethers@5.7.2';
import { isProposer as _isProposer } from '../_shared/isProposer.ts';
import { insertReply } from '../_shared/insertReply.ts';
import { corsHeaders } from '../_shared/cors.ts';

serve(async req => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const INFURA_PROJECT_ID = Deno.env.get('INFURA_PROJECT_ID');

  const provider = new ethers.providers.JsonRpcProvider(INFURA_PROJECT_ID);
  const { userAddress, communityAddress, blockTag, proposalId, content } = await req.json();

  const hasVotingPower = await prophouse.getVotingPower(
    userAddress,
    communityAddress,
    provider,
    blockTag,
  );
  const isProposer = await _isProposer(userAddress, proposalId);

  const canReply = isProposer || hasVotingPower > 0;

  if (!canReply)
    return new Response(
      JSON.stringify({ error: `${userAddress} is not allowed to reply to proposal ${proposalId}` }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      },
    );

  try {
    insertReply(userAddress, proposalId, content);
    return new Response(
      JSON.stringify({ success: `${userAddress} added a reply to proposal ${proposalId}` }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: `error inserting reply into db. error: ${error}` }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      },
    );
  }
});
