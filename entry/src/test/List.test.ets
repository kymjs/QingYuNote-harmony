import localUnitTest from './LocalUnit.test';
import markdownUtilsTest from './MarkdownUtils.test';
import cryptoServiceTest from './CryptoService.test';
import noteContentEncryptionServiceTest from './NoteContentEncryptionService.test';
import noteSortUtilsTest from './NoteSortUtils.test';
import noteStateCodecTest from './NoteStateCodec.test';

export default function testsuite() {
  localUnitTest();
  markdownUtilsTest();
  cryptoServiceTest();
  noteContentEncryptionServiceTest();
  noteSortUtilsTest();
  noteStateCodecTest();
}