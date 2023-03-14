import clsx from 'clsx';
import classes from './VotingModule.module.css';
import { Dispatch, SetStateAction, useEffect, useState } from 'react';
import { ProgressBar } from 'react-bootstrap';
import { MdHowToVote as VoteIcon } from 'react-icons/md';
import { useAppSelector } from '../../hooks';
import { countVotesRemainingForTimedRound } from '../../utils/countVotesRemainingForTimedRound';
import { countTotalVotesAlloted } from '../../utils/countTotalVotesAlloted';
import Button, { ButtonColor } from '../Button';
import RoundModuleCard from '../RoundModuleCard';
import { countNumVotes } from '../../utils/countNumVotes';
import ConnectButton from '../ConnectButton';
import { useTranslation } from 'react-i18next';
import { useAccount } from 'wagmi';

export interface VotingModuleProps {
  communityName: string;
  totalVotes: number | undefined;
  setShowVotingModal: Dispatch<SetStateAction<boolean>>;
}
const VotingModule: React.FC<VotingModuleProps> = (props: VotingModuleProps) => {
  const { communityName, totalVotes, setShowVotingModal } = props;
  const { address: account } = useAccount();

  const voteAllotments = useAppSelector(state => state.voting.voteAllotments);
  const votingPower = useAppSelector(state => state.voting.votingPower);
  const votesByUserInActiveRound = useAppSelector(state => state.voting.votesByUserInActiveRound);
  const numVotesByUserInActiveRound = countNumVotes(votesByUserInActiveRound);

  const [votesLeftToAllot, setVotesLeftToAllot] = useState(0);
  const [numAllotedVotes, setNumAllotedVotes] = useState(0);

  const { t } = useTranslation();

  useEffect(() => {
    setVotesLeftToAllot(
      countVotesRemainingForTimedRound(votingPower, votesByUserInActiveRound, voteAllotments),
    );
    setNumAllotedVotes(countTotalVotesAlloted(voteAllotments));
  }, [votesByUserInActiveRound, voteAllotments, votingPower]);

  const content = (
    <>
      <div className={classes.sideCardHeader}>
        <div className={clsx(classes.icon, classes.purpleIcon)}>
          <VoteIcon />
        </div>
        <div className={classes.textContainer}>
          <p className={classes.title}>{t('votingInProgress')}</p>
          <p className={classes.subtitle}>
            <span className={classes.purpleText}>{totalVotes}</span>{' '}
            {totalVotes === 1 ? t('vote') : t('votes')} {t('castSoFar')}!
          </p>
        </div>
      </div>

      <hr className={classes.divider} />

      {account ? (
        votingPower > 0 ? (
          <>
            <h1 className={clsx(classes.sideCardTitle, classes.votingInfo)}>
              <span>{t('castYourVotes')}</span>

              <span className={classes.totalVotes}>{`${
                votesLeftToAllot > 0
                  ? `${votingPower - numVotesByUserInActiveRound - numAllotedVotes} ${t('left')}`
                  : t('noVotesLeft')
              }`}</span>
            </h1>

            <ProgressBar
              className={clsx(
                classes.votingBar,
                numVotesByUserInActiveRound > 0 &&
                  votingPower !== numVotesByUserInActiveRound &&
                  'roundAllotmentBar',
              )}
            >
              <ProgressBar
                variant="success"
                now={(numVotesByUserInActiveRound / votingPower) * 100}
              />

              <ProgressBar variant="warning" now={(numAllotedVotes / votingPower) * 100} key={2} />
            </ProgressBar>
          </>
        ) : (
          <p className={classes.subtitle}>
            <b>
              {t('youDontHaveAny')} {communityName} {t('requiredToVote')}.
            </b>
          </p>
        )
      ) : (
        <p className={classes.sideCardBody}>
          <b>{t('proposers')}:</b>
          <div className={classes.bulletList}>
            <div className={classes.bulletItem}>
              <p>{t('connectToViewPropStatus')}.</p>
            </div>
          </div>

          <b>{t('voters')}:</b>
          <div className={classes.bulletList}>
            <div className={classes.bulletItem}>
              <p>{t('connectToVoteOnProps')}</p>
            </div>
          </div>
        </p>
      )}
    </>
  );

  const buttons = !account ? (
    <ConnectButton text={t('connectToVote')} color={ButtonColor.Pink} />
  ) : account && votingPower ? (
    <Button
      text={t('submitVotes')}
      bgColor={ButtonColor.Purple}
      onClick={() => setShowVotingModal(true)}
      disabled={
        countTotalVotesAlloted(voteAllotments) === 0 || numVotesByUserInActiveRound === votingPower
      }
    />
  ) : (
    //  VOTING PERIOD, CONNECTED, HAS NO VOTES
    <></>
  );

  return <RoundModuleCard content={content} buttons={buttons} />;
};

export default VotingModule;
