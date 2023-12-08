import { RoundEventState } from '@prophouse/sdk/dist/gql/evm/graphql';
import { Round_OrderBy } from '@prophouse/sdk-react';
import { RoundsFilter } from '../hooks/useRoundsFilter';
import { PropHouse, RoundWithHouse, Timed } from '@prophouse/sdk-react';

export const fetchRoundsForFilter = async (
  propHouse: PropHouse,
  account: string | undefined,
  favorites: string[],
  filter: RoundsFilter,
  pageIndex: number,
  perPage: number,
): Promise<RoundWithHouse[]> => {
  const queryParams = {
    page: pageIndex,
    perPage,
  };

  const now = Math.round(new Date().getTime() / 1000);

  const defaultQuery = propHouse.query.getRoundsWithHouseInfo({
    ...queryParams,
    where: {
      eventState_not: RoundEventState.Cancelled,
      house_not: '0x303979efeac12eca24c8ee1df118e44504ab1d2d', // Solimander Testing 🤫
      timedConfig_: {
        proposalPeriodStartTimestamp_lte: now,
        votePeriodEndTimestamp_gte: now,
      },
      balances_: {
        balance_gt: 0,
      },
    },
  });

  const query =
    filter === RoundsFilter.Active // active
      ? defaultQuery
      : filter === RoundsFilter.Favorites // favorites
      ? propHouse.query.getRoundsWithHouseInfo({
          ...queryParams,
          where: {
            house_in: favorites,
          },
        })
      : filter === RoundsFilter.Relevant && account // relevant + account is connected
      ? propHouse.query.getRoundsWithHouseInfoRelevantToAccount(account, queryParams)
      : filter === RoundsFilter.Recent
      ? propHouse.query.getRoundsWithHouseInfo({ ...queryParams, orderBy: Round_OrderBy.CreatedAt })
      : null; // relevant but account is not connected

  if (!query) return [];

  let rounds;
  const queryRounds = await query;
  rounds = queryRounds.length === 0 ? await defaultQuery : queryRounds;

  return rounds.filter(
    r => !(r.isFullyFunded === false && r.state === Timed.RoundState.IN_VOTING_PERIOD),
  );
};