import { FC, useState } from 'react';
import Divider from '../../Divider';
import DualSectionSelector from '../DualSectionSelector';
import Group from '../Group';
import Section from '../Section';
import { useAppSelector } from '../../../hooks';
import { AssetType } from '@prophouse/sdk';
import SplitAwards from '../SplitAwards';
import { ERC20 } from '../WhoCanParticipate';
import IndividualAwards from '../IndividualAwards';
import { uuid } from 'uuidv4';
import { checkStepCriteria, NewRound, updateRound } from '../../../state/slices/round';
import { useDispatch } from 'react-redux';

export interface Award {
  id: string;
  type: AssetType;
  address: string;
  tokenId?: string;
  image: string;
  name: string;
  symbol: string;
  amount: number;
  selectedAsset: ERC20 | null;
  price: number;
  state: 'input' | 'success' | 'error' | 'dummy';
  error?: string;
}

export const NewAward: Award = {
  id: uuid(),
  type: AssetType.ETH,
  address: '',
  tokenId: '',
  image: '/manager/eth.png',
  name: 'ETH',
  symbol: 'ETH',
  selectedAsset: null,
  amount: 1,
  state: 'input',
  price: 0,
  error: '',
};

const AssetSelector: FC<{
  editMode?: boolean;
  editedRound?: NewRound;
  setEditedRound?: React.Dispatch<React.SetStateAction<NewRound>>;
}> = props => {
  const { editMode, editedRound, setEditedRound } = props;

  const round = useAppSelector(state => state.round.round);
  const dispatch = useDispatch();

  const initialIndividualAwards: Award[] = [
    { ...NewAward, id: uuid(), state: 'dummy' },
    { ...NewAward, id: uuid(), state: 'dummy' },
    { ...NewAward, id: uuid(), state: 'dummy' },
  ];

  const [splitAwards, setSplitAwards] = useState<Award[]>(
    round.awards.length ? [...round.awards] : [],
  );
  const [individualAwards, setIndividualAwards] = useState<Award[]>(
    round.awards[0] && round.awards[0].id !== NewAward.id ? round.awards : initialIndividualAwards,
  );

  const [isSplitAward, setIsSplitAward] = useState(round.splitAwards);

  const changeAwardType = () => {
    if (editMode && editedRound) {
      const newAwards = Array.from({ length: editedRound.numWinners }, () => ({
        ...editedRound.awards[0],
        id: uuid(),
      }));

      // Find an existing ETH or ERC20 award in the individual awards array
      const baseAward = editedRound.awards.find(
        award => award.type === AssetType.ETH || award.type === AssetType.ERC20,
      );

      setEditedRound!({
        ...editedRound,
        splitAwards: !editedRound.splitAwards,
        awards: editedRound.splitAwards ? newAwards : [baseAward || NewAward],
      });
    } else {
      const updated = { ...round, splitAwards: !isSplitAward, numWinners: 1, awards: [] };

      if (isSplitAward) {
        setIndividualAwards(initialIndividualAwards);
      } else {
        setSplitAwards([NewAward]);
      }

      dispatch(updateRound(updated));
      dispatch(checkStepCriteria());
    }

    // Toggle the isSplitAward state at the end of the function
    setIsSplitAward(!isSplitAward);
  };

  return (
    <>
      <Group>
        <DualSectionSelector onChange={changeAwardType}>
          <Section
            active={isSplitAward}
            title="Split Awards"
            text="Choose the number of winners and the total payment to split between them."
          />
          <Section
            active={!isSplitAward}
            title="Inidividual Awards"
            text="Choose a reward individually for each of the winners."
          />
        </DualSectionSelector>
      </Group>

      <Divider />

      {isSplitAward ? (
        <SplitAwards
          editMode={editMode}
          awards={editMode ? editedRound!.awards : splitAwards}
          setAwards={setSplitAwards}
          editedRound={editedRound}
          setEditedRound={setEditedRound}
        />
      ) : (
        <IndividualAwards
          editMode={editMode}
          awards={editMode ? editedRound!.awards : individualAwards}
          setAwards={setIndividualAwards}
          setEditedRound={setEditedRound}
          editedRound={editedRound}
        />
      )}
    </>
  );
};

export default AssetSelector;
