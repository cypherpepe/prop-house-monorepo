import classes from './ProposalModalNavButtons.module.css';
import { ImArrowLeft2, ImArrowRight2 } from 'react-icons/im';
import { Direction } from '@nouns/prop-house-wrapper/dist/builders';

const ProposalModalNavButtons: React.FC<{
  propIndex: number | undefined;
  numberOfProps: number;
  handleDirectionalArrowClick: (e: any) => void;
}> = props => {
  const { propIndex, numberOfProps, handleDirectionalArrowClick } = props;

  return (
    <>
      <div className={classes.btnContainer}>
        <div className={classes.propNavigationButtons}>
          <button
            disabled={propIndex === 1}
            onClick={() => handleDirectionalArrowClick(Direction.Down)}
          >
            <ImArrowLeft2 size={'1.5rem'} />
            <span>Back</span>
          </button>

          <button
            onClick={() => handleDirectionalArrowClick(Direction.Up)}
            disabled={propIndex === numberOfProps}
          >
            <span>Next</span> <ImArrowRight2 size={'1.5rem'} />
          </button>
        </div>
      </div>
    </>
  );
};

export default ProposalModalNavButtons;
